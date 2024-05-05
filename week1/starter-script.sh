#!/bin/bash

# Set variables
S3_BUCKET_NAME="deenstatic"
CLOUDFRONT_DIST_NAME="deen-static-cdn"
DOMAIN_NAME="s3.mmuyideen.xyz"
ACM_CERT_ARN="your-acm-cert-arn"


# Create S3 bucket
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region us-east-1

# upload web files
aws s3 cp web/ s3://$S3_BUCKET_NAME/ --recursive

# Configure static website hosting
aws s3 website s3://$S3_BUCKET_NAME/ --index-document index.html

# enable public access
aws s3api put-public-access-block \
  --bucket $S3_BUCKET_NAME \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# attach bucket policy
aws s3api put-bucket-policy \
  --bucket $S3_BUCKET_NAME \
  --policy file://policy.json

echo "Certificate ARN: $certificate_arn"

# Run the aws acm request-certificate command and capture the output
certificate_arn=$(aws acm request-certificate --domain-name $DOMAIN_NAME --validation-method DNS --region us-east-1 | jq -r '.CertificateArn')

# Print the ARN
echo "Certificate ARN: $certificate_arn"


# Wait for ACM certificate validation
# Note: This step may take a few minutes
echo "Waiting for ACM certificate validation..."
aws acm wait certificate-validated --certificate-arn $certificate_arn --region us-east-1

# Create CloudFront distribution
aws cloudfront create-distribution \
  --origin-domain-name $S3_BUCKET_NAME.s3-website-us-east-1.amazonaws.com \
  --default-root-object index.html \
  --region us-east-1


# Get CloudFront distribution ID
CLOUDFRONT_DIST_ID=$(aws cloudfront list-distributions --query 'DistributionList.Items[?Aliases.Items[0] == `'$DOMAIN_NAME'`].Id' --output text --region us-east-1)

# Update DNS records in Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id $ROUTE53_HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "'$DOMAIN_NAME'",
          "Type": "A",
          "AliasTarget": {
            "DNSName": "'$CLOUDFRONT_DIST_NAME'.cloudfront.net",
            "HostedZoneId": "Z2FDTNDATAQYW2" # CloudFront zone ID
          }
        }
      }
    ]
  }' \
  --region us-east-1

# Output CloudFront distribution details
echo "CloudFront distribution created successfully!"
echo "Distribution ID: $CLOUDFRONT_DIST_ID"
echo "Domain Name: $DOMAIN_NAME"
