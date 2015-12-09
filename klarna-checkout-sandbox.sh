#!/bin/sh

# default
HTTP_PORT=8080

trap cleanup INT

function cleanup() {
	kill $$ # self pid
}

usage() {
cat << EOF
    Usage: $0 [options] <merchant id> <shared secret>

    This script starts a minimal web server providing an easy to use interface for a Klarna Checkout sandbox.
    
    EXAMPLE:
        $0 1234 YourSharedSecretHere

    OPTIONS:
       -h      Show this help message
       -p      HTTP server port. Default is 8080

EOF
}

# read options
while getopts "hp:" OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        p)
            HTTP_PORT=$OPTARG
            ;;
        ?)
            exit 1
            ;;
    esac
done

# merchant id and shared secret must be passed as arguments
MERCHANT_ID=${@:$OPTIND:1}
SHARED_SECRET=${@:$OPTIND+1:1}

if [ -z "$MERCHANT_ID" ]
then
	echo "You must specify your Klarna Checkout merchant id. For help see -h"
	exit 1
fi

if [ -z "$SHARED_SECRET" ]
then
	echo "You must specify your shared secret for Klarna Checkout. For help see -h"
	exit 1
fi

# Klarna Checkout test drive. DO NOT USE THIS SCRIPT WITH THE PRODUCTION API
API_URL="https://checkout.testdrive.klarna.com/checkout/orders"

create_digest() {
	PAYLOAD=$1
	
	DIGEST=$(php -r '$payload=$argv[1]; $sharedSecret=$argv[2]; echo base64_encode(hash("sha256", "{$payload}{$sharedSecret}", true));' "$PAYLOAD" "$SHARED_SECRET")
	
	echo "$DIGEST"
}

create_order() {
	AUTHORIZATION_STRING=$(create_digest "$PAYLOAD" "$SHARED_SECRET")
	
	CURL_CREATE_ORDER=$(curl -vsX POST \
		--header "Accept: application/vnd.klarna.checkout.aggregated-order-v2+json" \
		--header "Content-Type: application/vnd.klarna.checkout.aggregated-order-v2+json" \
		--header "Authorization: Klarna $AUTHORIZATION_STRING" \
		-d "$PAYLOAD" \
		"$API_URL" 2>&1)
	
	ORDER_LOCATION=$(echo "$CURL_CREATE_ORDER" | grep -oE "Location: (.*)" | cut -d " " -f 2 | tr -d "\r")
	echo "$ORDER_LOCATION"
}

get_order_snippet() {
	ORDER_LOCATION=$1
	
	PAYLOAD="" # empty payload for GET requests
	AUTHORIZATION_STRING=$(create_digest "$PAYLOAD" "$SHARED_SECRET")
	
	CURL_GET_ORDER=$(curl -vs \
		--header "Accept: application/vnd.klarna.checkout.aggregated-order-v2+json" \
		--header "Authorization: Klarna $AUTHORIZATION_STRING" \
		"$ORDER_LOCATION" 2>&1)
	
	KLARNA_CHECKOUT_SNIPPET=$(echo "$CURL_GET_ORDER" | perl -0777 -ne 'print $1 if /\"snippet\":\"(.*?)\"},/s' | sed 's/\\\"/"/g')
	echo "$KLARNA_CHECKOUT_SNIPPET"
}

echo "[`date '+%Y-%m-%d %H:%M:%S'`] Listening for requests. To create a sample order and get it's snippet send a request to http://127.0.0.1:$HTTP_PORT/order"

# creds to http://paulbuchheit.blogspot.ro/2007/04/webserver-in-bash.html which inspired this fifo and nc solution
RESPONSE=/tmp/klarna-checkout-sandbox-response
[ -p $RESPONSE ] || mkfifo $RESPONSE

while true
do
	( cat $RESPONSE ) | nc -l $HTTP_PORT | (
	REQUEST=`while read L && [ " " "<" "$L" ] ; do echo "$L" ; done`
	echo "[`date '+%Y-%m-%d %H:%M:%S'`] $REQUEST" | head -1
	
	# extract request type and requested resource
	REQUEST_TYPE_AND_RESOURCE=$(echo "$REQUEST" | head -1 | perl -ne '/(.*?) (.*?) HTTP/ && print "$1,$2"')
	REQUEST_TYPE=$(echo "$REQUEST_TYPE_AND_RESOURCE" | cut -d "," -f 1)
	REQUEST_RESOURCE=$(echo "$REQUEST_TYPE_AND_RESOURCE" | cut -d "," -f 2)
	
	if [ "$REQUEST_RESOURCE" != "/order" ]
	then
		RESPONSE_CODE_STRING="404 Not Found"
		RESPONSE_BODY=""
	else
		RESPONSE_CODE_STRING="200 OK"
		
		echo "[`date '+%Y-%m-%d %H:%M:%S'`] Creating order..."
	
		# use specified merchant id
		PAYLOAD_TEMPLATE="{ \"merchant_reference\": { \"orderid1\": \"123456789\", \"orderid2\": \"123456789\" }, \"purchase_country\": \"se\", \"purchase_currency\": \"sek\", \"locale\": \"sv-se\", \"cart\": { \"items\": [ { \"reference\": \"123456789\", \"name\": \"Klarna t-shirt\", \"quantity\": 2, \"ean\": \"1234567890123\", \"uri\": \"http://example.com/product.php?123456789\", \"image_uri\": \"http://example.com/product_image.php?123456789\", \"unit_price\": 12300, \"discount_rate\": 1000, \"tax_rate\": 2500 }, { \"type\": \"shipping_fee\", \"reference\": \"SHIPPING\", \"name\": \"Shipping fee\", \"quantity\": 1, \"unit_price\": 4900, \"tax_rate\": 2500 } ] }, \"shipping_address\": { \"given_name\": \"Testperson-se\", \"family_name\": \"Approved\", \"street_address\": \"Stårgatan 1\", \"postal_code\": \"12345\", \"city\": \"Ankeborg\", \"country\": \"se\", \"email\": \"checkout@testdrive.klarna.com\", \"phone\": \"0765260000\" }, \"gui\": { \"layout\": \"desktop\" }, \"merchant\": { \"id\": \"%MERCHANT_ID_HERE%\", \"back_to_store_uri\": \"http://example.com\", \"terms_uri\": \"http://example.com/terms.php\", \"checkout_uri\": \"https://example.com/checkout.php\", \"confirmation_uri\": \"https://example.com/thankyou.php?sid=123&klarna_order={checkout.order.uri}\", \"push_uri\": \"https://example.com/push.php?sid=123&klarna_order={checkout.order.uri}\" } }"
		PAYLOAD=$(echo "$PAYLOAD_TEMPLATE" | sed "s/%MERCHANT_ID_HERE%/$MERCHANT_ID/g")
		
		# create order and then get it's snippet
		ORDER_LOCATION=$(create_order "$PAYLOAD")
		KLARNA_CHECKOUT_SNIPPET=$(get_order_snippet "$ORDER_LOCATION")
		echo "[`date '+%Y-%m-%d %H:%M:%S'`] Order info retrieved."
		
		RESPONSE_BODY="$KLARNA_CHECKOUT_SNIPPET"
	fi
	
	cat > $RESPONSE << EOF
HTTP/1.0 $RESPONSE_CODE_STRING
Cache-Control: private
Content-type: text/html
Server: Klarna Checkout Sandbox/1.0
Connection: Close
Content-Length: ${#RESPONSE_BODY}

$RESPONSE_BODY
EOF

	echo "[`date '+%Y-%m-%d %H:%M:%S'`] Response sent"
	)
done
