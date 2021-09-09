import boto3

def lambda_handler(event,context):
    ssm = boto3.client('ssm')
    response = ssm.get_parameter(
        Name='foo',
    )
    print(response['Parameter']['Value'])

if __name__== "__main__":
    handler(None,None)
