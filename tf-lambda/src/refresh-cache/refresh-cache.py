import boto3
import requests
import os
import json
import logging

# --- Setup Logging ---
# Best practice to set up logging for better debugging in CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- Configuration from Environment Variables ---
# Make your function configurable without changing code
SSM_USER_PARAM = os.environ.get('SSM_USER_PARAM', '/bcch/username')
SSM_PASS_PARAM = os.environ.get('SSM_PASS_PARAM', '/bcch/password')
DYNAMO_TABLE_NAME = os.environ.get('DYNAMO_TABLE_NAME', 'unemployment-storage')
API_BASE_URL = "https://si3.bcentral.cl/SieteRestWS/SieteRestWS.ashx"
TSR_UNEMPLOYMENT = "F049.DES.TAS.INE9.10.M"

# --- AWS Clients & Secret Initialization (outside the handler) ---
# This code runs only during a "cold start", making subsequent invocations faster.
try:
    logger.info("Initializing AWS clients and fetching secrets...")
    ssm_client = boto3.client('ssm')
    dynamodb_resource = boto3.resource('dynamodb')
    
    # Fetch parameters from SSM
    user_param = ssm_client.get_parameter(Name=SSM_USER_PARAM, WithDecryption=True)
    pass_param = ssm_client.get_parameter(Name=SSM_PASS_PARAM, WithDecryption=True)
    
    API_USER = user_param['Parameter']['Value']
    API_PASSWORD = pass_param['Parameter']['Value']

    # Get a handle on the DynamoDB table
    dynamo_table = dynamodb_resource.Table(DYNAMO_TABLE_NAME)
    logger.info("Initialization successful.")

except Exception as e:
    logger.error(f"FATAL: Could not initialize environment: {e}")
    # This will cause subsequent invocations to fail until the issue is resolved
    API_USER = None
    API_PASSWORD = None


def lambda_handler(event, context):
    """
    Main Lambda handler function.
    - Constructs the API URL from the event payload.
    - Fetches data from the external API.
    - Stores the result in a DynamoDB table.
    """
    if not all([API_USER, API_PASSWORD]):
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Secrets not configured. Check function logs.'})
        }

    # --- 1. Extract query parameters from the Lambda event ---
    logger.info(f"Received event: {event}")
    # Use .get() to avoid errors if a key is missing
    timeseries = event.get('timeseries')
    firstdate = event.get('firstdate') # Optional
    lastdate = event.get('lastdate')   # Optional

    # --- 2. Build the request URL ---
    # Construct the query parameter string dynamically
    params = {
        'user': API_USER,
        'pass': API_PASSWORD,
        'timeseries': TSR_UNEMPLOYMENT,
        'function': 'GetSeries'
    }
    if firstdate:
        params['firstdate'] = firstdate
    if lastdate:
        params['lastdate'] = lastdate

    # --- 3. Make the HTTP request to the external API ---
    try:
        logger.info("Requesting data for BCCH unemployment rate")
        response = requests.get(API_BASE_URL, params=params, timeout=15)
        response.raise_for_status()  # Raises an exception for bad status codes (4xx or 5xx)
        
        api_data = response.json()
        logger.info("Successfully received data from API.")

    except requests.exceptions.RequestException as e:
        logger.error(f"API Request Failed: {e}")
        return {
            'statusCode': 502, # Bad Gateway
            'body': json.dumps({'error': 'Failed to fetch data from external API.'})
        }

    # --- 4. Store the result in DynamoDB ---
    try:
        # Your table's primary key is 'id'. We'll use the timeseries identifier for it.
        # This will overwrite any existing item with the same timeseries ID.
        item_to_store = {
            'id': timeseries,
            'data': api_data # Store the entire JSON response
            # You could add other attributes like a timestamp:
            # 'last_updated_utc': datetime.utcnow().isoformat()
        }
        
        logger.info(f"Putting item into DynamoDB table: {DYNAMO_TABLE_NAME}")
        dynamo_table.put_item(Item=item_to_store)
        
        logger.info(f"Successfully stored item for id: {timeseries}")

    except Exception as e:
        logger.error(f"DynamoDB Put Failed: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to store data in DynamoDB.'})
        }

    # --- 5. Return a successful response ---
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f"Successfully fetched and stored data for timeseries: {timeseries}",
            'retrieved_data': api_data
        })
    }