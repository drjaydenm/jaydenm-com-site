#!/bin/bash
SKIP_CONFIRM=${SKIP_CONFIRM:-false}
BUCKET_NAME=jaydenm.com

echo "Bucket Name: $BUCKET_NAME"
echo "Running S3 sync in dry-run mode..."
aws s3 sync public/ s3://$BUCKET_NAME --exclude ".DS_Store" --delete --cache-control 'max-age=86400' --dryrun

if ! $SKIP_CONFIRM
then
    read -r -p "Do you want to run the real sync? [y/N] " response
    if ! [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
    then
        echo "Aborting"
        exit
    fi
fi

echo "Running the real sync..."
aws s3 sync public/ s3://$BUCKET_NAME --exclude ".DS_Store" --exclude "*.html" --delete --cache-control 'max-age=86400'

echo "Disabling caching on HTML files..."
aws s3 sync public/ s3://$BUCKET_NAME --exclude "*" --include "*.html" --cache-control 'max-age=0'

echo "Sync complete"

echo "Finding CloudFront distribution ID for Origin $BUCKET_NAME"
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[].{Id: Id, OriginDomainName: Origins.Items[0].DomainName}[?contains(OriginDomainName, '$BUCKET_NAME')] | [0].Id" | tr -d \")
echo "CloudFront distribution ID: $DISTRIBUTION_ID"

echo "Running CloudFront invalidation"
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths /\*
echo "CloudFront invalidation successful"

echo "Publish Complete!"
