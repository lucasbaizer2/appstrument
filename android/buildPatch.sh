#!/bin/bash

set +x
set -e

./gradlew build

RELEASE_DIR=./app/build/outputs/apk/release
java -jar ../client/assets/java/apktool.jar decode $RELEASE_DIR/app-release-unsigned.apk --output $RELEASE_DIR/app-release-unsigned --force

cd $RELEASE_DIR/app-release-unsigned

cd smali/appstrument/server
rm 'R$dimen.smali'
rm BuildConfig.smali
cd ../../..

rm -rf original res apktool.yml

PATCH_FILE=../../../../../../../client/assets/java/patch.zip

set +e
rm $PATCH_FILE
set -e

zip -r $PATCH_FILE *

cd ..
rm -rf app-release-unsigned
