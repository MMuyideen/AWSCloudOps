#!/bin/bash

# Set the necessary variables
BUCKET_NAME="your-bucket-name"
DOMAIN_NAME="example.com"
HOSTED_ZONE_ID="your-hosted-zone-id"
REGION="us-east-1"

# Create an S3 bucket with static website hosting enabled
aws s3 mb s3://$BUCKET_NAME --region $REGION
aws s3 website s3://$BUCKET_NAME --index-document index.html --error-document error.html

# Request an SSL/TLS certificate from ACM
CERTIFICATE_ARN=$(aws acm request-certificate --domain-name $DOMAIN_NAME --validation-method DNS --idempotency-token $(uuid) --query CertificateArn --output text)

# Validate the certificate using DNS
RECORD_VALUE=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --query Certificate.DomainValidationOptions[0].ResourceRecord.Value --output text)
RECORD_NAME=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --query Certificate.DomainValidationOptions[0].ResourceRecord.Name --output text)

aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch '{"Changes":[{"Action":"CREATE","ResourceRecordSet":{"Name":"'"$RECORD_NAME"'","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"'"$RECORD_VALUE"'"}]}}]}'

# Wait for the certificate to be validated
aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN

# Create a CloudFront distribution
DISTRIBUTION_ID=$(aws cloudfront create-distribution --origin-domain-name $BUCKET_NAME.s3.amazonaws.com --default-root-object index.html --viewer-certificate cloudfront-default-certificate=false,minimum-protocol-version=TLSv1.2_2021,ssl-support-method=sni-only,acm-certificate-arn=$CERTIFICATE_ARN --enabled --default-cache-behavior-forwarded-values '{"QueryString":true,"Cookies":{"Forward":"none"}}' --default-cache-behavior-min-ttl 0 --default-cache-behavior-max-ttl 300 --default-cache-behavior-default-ttl 86400 --price-class PriceClass_100 --aliases $DOMAIN_NAME --query Distribution.Id --output text)

# Create a Route 53 record for the domain
aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch '{"Changes":[{"Action":"CREATE","ResourceRecordSet":{"Name":"'"$DOMAIN_NAME"'","Type":"A","AliasTarget":{"HostedZoneId":"Z2FDTNDATAQYW2","DNSName":"'"$DISTRIBUTION_ID"'.cloudfront.net","EvaluateTargetHealth":false}}}]}'

echo "Bucket name: $BUCKET_NAME"
echo "Domain name: $DOMAIN_NAME"
echo "CloudFront distribution ID: $DISTRIBUTION_ID"