#!/bin/sh

VERSION=1.0.0
DOMAIN='<domain in cloudron to install this app>'
AUTHOR='<your name>'

docker build -t $AUTHOR/cloudron-erpnext:$VERSION ./ && docker push $AUTHOR/cloudron-erpnext:$VERSION

cloudron install --image $AUTHOR/cloudron-erpnext:$VERSION -l $DOMAIN

cloudron logs -f --app $DOMAIN
