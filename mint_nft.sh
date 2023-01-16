#!/bin/bash

# This is a bash script for minting Cardano NFTs
# Script is based on instructions provided in:
# https://developers.cardano.org/docs/native-tokens/minting-nfts/
# Author: @ADAlchemist
# !!! Use this script at your own risk !!!

# Variables for the policy
# policy expiration in seconds. 86400 = you have one day (24h) to fix things if mistakes happened in mint
export expiry=86400

# Variables for the NFT
export realtokenname="ADAlchemist"
export tokenname=$(echo -n $realtokenname | xxd -b -ps -c 80 | tr -d '\n')
export ar_hash="dkXRrMWTxcj9eQ7XzuR9te-U450cSi8omn90uW64c2U"
export website="https://github.com/ADAAlchemist"
export description="Test mint created with Daedalous node"
export name="ADAlchemist NFT token"

export tokenamount="1"
export fee="0"
export output="0"


# Check that wallet address has been provided as an argument
echo "NFT mint script for Daedalous"
if [ $# -eq 0 ]; then
    echo "usage: $0 [recipient wallet address]"
    exit 0
fi

# network
# set this to preprod or mainnet
export NETWORK="preprod"
# export NETWORK="mainnet"
echo "Selected network: $NETWORK"

if [ $NETWORK = "preprod" ]
then
    # cardano-cli attribute for preprod
    export NET="--testnet-magic 1"
    # Daedalus socet path for preprod
    export CARDANO_NODE_SOCKET_PATH=$(ps ax | grep -v grep | grep cardano-wallet | grep testnet | sed -E 's/(.*)node-socket //')
elif [ $NETWORK = "mainnet" ]
then
    echo "***********************************************************************"    
    echo "* !!!WARNING!!! This mint will be performed in mainnet with real ADA. *"
    echo "* Make sure that you fully understand how this script works.          *"
    echo "* Author of this script is not liable for any possible losses caused  *"
    echo "* by using this script.                                               *"
    echo "***********************************************************************"
    export NET="--mainnet"
    export CARDANO_NODE_SOCKET_PATH=$(ps ax | grep -v grep | grep cardano-wallet | grep mainnet | sed -E 's/(.*)node-socket //')
else
    echo "define NETWORK as preprod or mainnet"
    exit 0
fi

# Check that the receive address is ok and Daedalus is running
cardano-cli get-tip $NET > tip.json 2>/dev/null

if [ $? -eq 0 ]; then
    currentslot=$(jq .slot tip.json)
    cardano-cli query utxo --address $1 $NET >/dev/null 2>/dev/null
    if [ $? -eq 0 ]
    then
        export receive_address=$1
    else
        echo "Invalid address $1"
        exit 0
    fi
else
    echo "Can't find Daedalous $NETWORK node."
    echo "Make sure you have the full node wallet running and in sync."
    exit 0
fi

# Payment address and keys
if test -f "payment.addr" -a -f "payment.skey" -a -f "payment.vkey"; then
    export address=$(cat payment.addr)
    echo "Using payment address: $address"
else
    echo "Payment files not found."
    read -p "Create new payment address?" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        cardano-cli address key-gen --verification-key-file payment.vkey --signing-key-file payment.skey
        cardano-cli address build --payment-verification-key-file payment.vkey --out-file payment.addr $NET
        echo "Payment address created:"
        echo $(cat payment.addr)
        echo "Fund the address with at least 2.6 ADA and run this script again."
        exit 0
    else
        echo "Copy existing address files: payment.addr, payment.skey and payment.vkey into this folder and run this script again."
        exit 0
    fi
fi

# Get TxHash and balance
cardano-cli query utxo --address $address $NET --out-file utxo.json
# jq '.' utxo.json

NUMOFUTXOS=$(expr $(jq length utxo.json))
VALUE=0

for i in $(seq $NUMOFUTXOS)
do
    TXHASH_RAW=$(expr $(jq 'keys'[$((i-1))] utxo.json))
    # echo $TXHASH_RAW
    # VALUELENGTH=$(expr $(jq --argjson i "$i" '[.[].value | select(.datum==null)][$i-1] | length' utxo.json))
    VALUELENGTH=$(expr $(jq --argjson i "$i" '[.[].value][$i-1] | length' utxo.json))
    # echo $VALUELENGTH
    if [ $VALUELENGTH = 1 ]
    then
        VALUE=$(expr $(jq --argjson i "$i" '[.[].value.lovelace][$i-1]' utxo.json))

        if [ $VALUE -ge 2600000 ]
        then
            # echo $VALUE
            break
        fi
    fi   
done

if [ $VALUE -ge 2600000 ]
then

    TXHASH=$(echo $TXHASH_RAW | cut -d '#' -f 1)
    TXHASH=${TXHASH:1}

    TXIX=$(echo $TXHASH_RAW | cut -d '#' -f 2)
    TXIX=${TXIX//\"/}

    echo "UTXO with sufficient balance found: $TXHASH#$TXIX"
    echo "Balance: $VALUE lovelace"

    export TXHASH
    export TXIX
    export BALANCE=$VALUE
else
    echo "Insufficient amount of ADA in payment address"
    echo "Fund this address with at least 2.6 ADA:"
    echo $address
    exit 0
fi

# export protocol parameters
if test -f "protocol.json"
then
    echo "protocol.json found."
else
    cardano-cli query protocol-parameters $NET --out-file protocol.json
    echo "protocol parameters fetched."
fi

# PolicyID
export script="policy/policy.script"
createpolicyprompt=false

if test -f "policy/policy.vkey" -a -f "policy/policy.skey"; then
    echo "Policy keys found"
else
    echo "Policy keys not found."
    read -p "Create new policy keys?" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        mkdir -p policy
        cardano-cli address key-gen \
        --verification-key-file policy/policy.vkey \
        --signing-key-file policy/policy.skey
    else
        echo "If you want to use existing keys, copy your policy files into policy folder "
        exit 0
    fi
fi

if test -f "policy/policyID" -a -f "policy/policy.script"; then
    echo "policy.script found:"
    export slotnumber=$(jq '.scripts[0].slot' policy/policy.script)
    if [ $slotnumber -lt $currentslot ]; then
        echo "Your policy has expired. You need to create a new policy in order to mint an NFT"
        createpolicyprompt=true
    fi

else
    echo "Policy not found."
    createpolicyprompt=true
fi

if [ "$createpolicyprompt" = true ]; then
    read -p "Create new policy?" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        mkdir -p policy
        export slotnumber=$(expr $(cardano-cli query tip $NET | jq .slot?) + $expiry)


        echo "{" >> $script
        echo "  \"type\": \"all\"," >> $script
        echo "  \"scripts\":" >> $script
        echo "  [" >> $script
        echo "   {" >> $script
        echo "     \"type\": \"before\"," >> $script
        echo "     \"slot\": $slotnumber" >> $script
        echo "   }," >> $script
        echo "   {" >> $script
        echo "     \"type\": \"sig\"," >> $script
        echo "     \"keyHash\": \"$(cardano-cli address key-hash --payment-verification-key-file policy/policy.vkey)\"" >> $script 
        echo "   }" >> $script
        echo "  ]" >> $script
        echo "}" >> $script

        cardano-cli transaction policyid --script-file ./policy/policy.script > policy/policyID
    else
        echo "Copy your existing policy files into policy folder and run this script again"
        exit 0
    fi
fi

echo "Policy script:"
jq . policy/policy.script
echo "This policy locks after $(( ($slotnumber - $currentslot) / 3600 )) hours."

export policyid=$(cat policy/policyID)

# Create metadata

rm -f metadata.json

echo "{" >> metadata.json
echo "  \"721\": {" >> metadata.json 
echo "    \"$(cat policy/policyID)\": {" >> metadata.json 
echo "      \"$(echo $realtokenname)\": {" >> metadata.json
echo "        \"name\": \"$(echo $name)\"," >> metadata.json
echo "        \"description\": \"$(echo $description)\"," >> metadata.json
echo "        \"image\": \"ar://$(echo $ar_hash)\"," >> metadata.json
echo "        \"website\": \"$(echo $website)\"" >> metadata.json
echo "      }" >> metadata.json
echo "    }" >> metadata.json 
echo "  }" >> metadata.json 
echo "}" >> metadata.json

echo
echo "NFT metadata:"
jq . metadata.json

# Build transaction

# get min UTXO
# this tansaction build will generate an error, which gives the minimum
# amount of lovelace needed as an error output
cardano-cli transaction build \
$NET \
--alonzo-era \
--tx-in $TXHASH#$TXIX \
--tx-out $receive_address+$output+"$tokenamount $policyid.$tokenname" \
--change-address $address \
--mint="$tokenamount $policyid.$tokenname" \
--minting-script-file $script \
--metadata-json-file metadata.json  \
--invalid-hereafter $slotnumber \
--witness-override 2 \
--out-file matx.raw \
2> min_UTXO.txt

export output=$(grep -oP 'Minimum required UTxO: Lovelace \K\d+' min_UTXO.txt)


#get fee
cardano-cli transaction build \
$NET \
--alonzo-era \
--tx-in $TXHASH#$TXIX \
--tx-out $receive_address+$output+"$tokenamount $policyid.$tokenname" \
--change-address $address \
--mint="$tokenamount $policyid.$tokenname" \
--minting-script-file $script \
--metadata-json-file metadata.json  \
--invalid-hereafter $slotnumber \
--witness-override 2 \
--out-file matx.raw \
> fee.txt

export fee=$(cat fee.txt | awk '{print $NF}')

export output=$(($output + $fee))

read -p "Are you ready to sign the transaction? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    #sign transaction
    rm -f matx.signed

    cardano-cli transaction sign  \
    --signing-key-file payment.skey  \
    --signing-key-file policy/policy.skey  \
    $NET --tx-body-file matx.raw  \
    --out-file matx.signed

    if test -f "matx.signed"
    then
        cardano-cli transaction submit --tx-file matx.signed $NET
    else
        echo "Signing the transaction failed."
    fi
fi