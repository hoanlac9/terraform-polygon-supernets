#!/bin/bash -x

main() {
    if [[ -d "/var/lib/bootstrap" ]]; then
        echo "It appears this network has already been boot strapped"
        exit
    fi
    mkdir /var/lib/bootstrap
    pushd /var/lib/bootstrap

{% for item in hostvars %}
{% if (hostvars[item].tags.Role == "fullnode" or hostvars[item].tags.Role == "validator") %}
    polygon-edge polybft-secrets --data-dir {{ hostvars[item].tags["Name"] }} --json --insecure > {{ hostvars[item].tags["Name"] }}.json
{% endif %}
{% endfor %}

{% if (enable_eip_1559) %}
    apt update
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    pushd /opt/polygon-edge/
    make compile-core-contracts
    cp -r /opt/polygon-edge/core-contracts /var/lib/bootstrap/core-contracts/
    popd

    BURN_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000000
{% endif %}

    polygon-edge genesis \
                 --consensus polybft \
                 {% for item in hostvars %}{% if (hostvars[item].tags.Role == "fullnode" or hostvars[item].tags.Role == "validator") %} --bootnode /dns4/{{ hostvars[item].tags["Name"] }}/tcp/{{ edge_p2p_port }}/p2p/$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].node_id') {% endif %}{% endfor %} \
                 {% for item in hostvars %}{% if (hostvars[item].tags.Role == "fullnode" or hostvars[item].tags.Role == "validator") %} --premine $(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].address'):1000000000000000000000000 {% endif %}{% endfor %} \
                 --premine {{ loadtest_account }}:1000000000000000000000000000 \
                 --reward-wallet 0x0101010101010101010101010101010101010101:1000000000000000000000000000 \
                 --block-gas-limit {{ block_gas_limit }} --block-time {{ block_time }}s \
                 {% for item in hostvars %}{% if (hostvars[item].tags.Role == "validator") %} --validators /dns4/{{ hostvars[item].tags["Name"] }}/tcp/{{ edge_p2p_port }}/p2p/$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].node_id'):$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].address' | sed 's/^0x//'):$(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].bls_pubkey') {% endif %}{% endfor %} \
                 --epoch-size 10 \
{% if (enable_eip_1559) %}
                 --burn-contract 0:$BURN_CONTRACT_ADDRESS \
{% endif %}
                 --native-token-config {{ native_token_config }}

{% if (enable_eip_1559) %}
    # EIP-1559
    jq --argjson code $(cat /var/lib/bootstrap/core-contracts/artifacts/contracts/child/EIP1559Burn.sol/EIP1559Burn.json)  \
       --arg balance "$BALANCE" \
       --arg addr "$BURN_CONTRACT_ADDRESS" \
       '.genesis.alloc += {($addr): {"code": $code.deployedBytecode, "balance": $balance}}' \
       genesis.json | jq . > tmp.json && mv tmp.json genesis.json
{% endif %}

    polycli wallet create --words 12 --language english | jq '.Addresses[0]' > rootchain-wallet.json

    # Should the deployer be funded from an unlocked L1 chain or from a prefunded account on L1
    {% if (not fund_rootchain_coinbase) %}# {% endif %}COINBASE_ADDRESS=$(cast rpc --rpc-url {{ rootchain_json_rpc }} eth_coinbase | sed 's/"//g')
    {% if (not fund_rootchain_coinbase) %}# {% endif %}cast send --rpc-url {{ rootchain_json_rpc }} --from $COINBASE_ADDRESS --value {{ rootchain_deployer_fund_amount }} $(cat rootchain-wallet.json | jq -r '.ETHAddress') --unlocked
    {% if (fund_rootchain_coinbase) %}# {% endif %}cast send --rpc-url {{ rootchain_json_rpc }} --from {{ rootchain_coinbase_address }} --value {{ rootchain_deployer_fund_amount }} $(cat rootchain-wallet.json | jq -r '.ETHAddress') --private-key {{ rootchain_coinbase_private_key }}

    polygon-edge rootchain deploy \
                 --deployer-key $(cat rootchain-wallet.json | jq -r '.HexPrivateKey') \
                 --json-rpc {{ rootchain_json_rpc }}

{% for item in hostvars %}
{% if (hostvars[item].tags.Role == "validator") %}
    cast send --rpc-url {{ rootchain_json_rpc }} --from $(cat rootchain-wallet.json | jq -r '.ETHAddress') --private-key $(cat rootchain-wallet.json | jq -r '.HexPrivateKey') \
         --value {{ rootchain_validator_fund_amount }} $(cat {{ hostvars[item].tags["Name"] }}.json | jq -r '.[0].address')
{% endif %}
{% endfor %}

    polygon-edge polybft whitelist-validators \
                 --private-key $(cat rootchain-wallet.json | jq -r '.HexPrivateKey') \
                 --addresses $(cat validator-*.json | jq -r ".[].address" | tr "\n" ",") \
                 --supernet-manager $(cat genesis.json | jq -r '.params.engine.polybft.bridge.customSupernetManagerAddr') \
                 --json-rpc {{ rootchain_json_rpc }}


{% for item in hostvars %}
{% if (hostvars[item].tags.Role == "validator") %}
    polygon-edge polybft register-validator --data-dir {{ hostvars[item].tags["Name"] }} \
                 --supernet-manager $(cat genesis.json | jq -r '.params.engine.polybft.bridge.customSupernetManagerAddr') \
                 --json-rpc {{ rootchain_json_rpc }}
{% endif %}
{% endfor %}

{% for item in hostvars %}
{% if (hostvars[item].tags.Role == "validator") %}
    polygon-edge polybft stake --data-dir {{ hostvars[item].tags["Name"] }} --chain-id $(cat genesis.json | jq -r '.params.chainID') \
                 --amount 10 \
                 --stake-manager $(cat genesis.json | jq -r '.params.engine.polybft.bridge.stakeManagerAddr') \
                 --native-root-token $(cat genesis.json | jq -r '.params.engine.polybft.bridge.nativeERC20Address') \
                 --json-rpc {{ rootchain_json_rpc }}
{% endif %}
{% endfor %}

    polygon-edge polybft supernet --private-key $(cat rootchain-wallet.json | jq -r '.HexPrivateKey') \
                 --supernet-manager $(cat genesis.json | jq -r '.params.engine.polybft.bridge.customSupernetManagerAddr') \
                 --stake-manager $(cat genesis.json | jq -r '.params.engine.polybft.bridge.stakeManagerAddr') \
                 --finalize-genesis --enable-staking \
                 --json-rpc {{ rootchain_json_rpc }}

    tar czf {{ base_dn }}.tar.gz *.json *.private
    popd
}

main
