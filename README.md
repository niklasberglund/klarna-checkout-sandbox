# klarna-checkout-sandbox
Whip up a Klarna Checkout sandbox in seconds. Provides a quick and easy to use interface for creating test orders in Klarna Checkout Test Drive and get their HTML snippet.

## Usage instructions
Make sure the script is executable(`chmod +x klarna-checkout-sandbox.sh`), run the script and make sure you pass your Klarna Checkout merchant id and shared secret as arguments.

`./klarna-checkout-sandbox.sh 4567 a6yQJFe1VldnBx9`

This will start a web server listening for GET requests on http://127.0.0.1:8080/order

See `./klarna-checkout-sandbox.sh -h` for more usage information.
