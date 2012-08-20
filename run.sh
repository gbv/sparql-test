#/!usr/bin/bash

PORT=9090

env RDF_ENDPOINT_BASE=/ \
    RDF_ENDPOINT_SHAREDIR=`pwd` \
    RDF_ENDPOINT_CONFIG=`pwd`/default.json \
    plackup -e development -r -p $PORT endpoint.psgi
