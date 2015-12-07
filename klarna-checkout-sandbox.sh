#!/bin/sh

# shared secret passed as argument
SHARED_SECRET=${@:$OPTIND:1}

# Klarna Checkout test drive. DO NOT USE THIS SCRIPT WITH THE PRODUCTION API
API_URL="https://checkout.testdrive.klarna.com/checkout/orders"

PAYLOAD=$(cat payload.json)

create_digest() {
	PAYLOAD=$1
	SHARED_SECRET=$2
	
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
	
	PAYLOAD=""
	AUTHORIZATION_STRING=$(create_digest "$PAYLOAD" "$SHARED_SECRET")
	
	CURL_GET_ORDER=$(curl -vs --header "Accept: application/vnd.klarna.checkout.aggregated-order-v2+json" --header "Authorization: Klarna $AUTHORIZATION_STRING" $ORDER_LOCATION)
	
	KLARNA_CHECKOUT_SNIPPET=$(echo "$CURL_GET_ORDER" | perl -0777 -ne 'print $1 if /\"snippet\":\"(.*?)\"},/s')
	echo $KLARNA_CHECKOUT_SNIPPET
}

ORDER_LOCATION=$(create_order)
echo "$ORDER_LOCATION"

KLARNA_CHECKOUT_SNIPPET=$(get_order_snippet "$ORDER_LOCATION")
echo $KLARNA_CHECKOUT_SNIPPET
