#!/bin/bash

protoc -I=. --dart_out=../client/lib/proto ./appstrument.proto ./data_model.proto
