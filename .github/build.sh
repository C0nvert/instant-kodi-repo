#!/bin/bash

# Adapted from https://gist.github.com/domenic/ec8b0fc8ab45f39403dd

set -e

CWD=$(pwd)
SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"

BUILD_DIR="$HOME/.build"
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

REPO_USER=$(echo "$TRAVIS_REPO_SLUG" | grep -Eo '^([^/]+)')
REPO_NAME=$(echo "$TRAVIS_REPO_SLUG" | grep -Eo '([^/]+)$')

git clone --quiet $REPO $BUILD_DIR

cd $BUILD_DIR
git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH

cd $CWD
# Clean out existing contents
rm -rf $BUILD_DIR/**/* || exit 0

python .github/build_repo_addon.py "$REPO_USER" "$REPO_NAME" "src/"

# Do our repo build
plugin_sources=''
for d in src/* ; do
    if [ -d "$d" ]; then
        if [ ! -z "$plugin_sources" ]; then
            # Append a space
            plugin_sources="$plugin_sources "
        fi
        plugin_sources="$plugin_sources$d"
    fi
done

create_repo_script_url='https://raw.githubusercontent.com/chadparry/kodi-repository.chad.parry.org/master/tools/create_repository.py'
create_repository_py='.github/create_repository.py'

wget -O "$create_repository_py" "$create_repo_script_url" || curl -o "$create_repository_py" "$create_repo_script_url"

# the datadir/ path is also hardcoded in build_repo_addon.py
mkdir -p "$BUILD_DIR/datadir/"
python "$create_repository_py" -d "$BUILD_DIR/datadir/" -i "$BUILD_DIR/addons.xml" -c "$BUILD_DIR/addons.xml.md5" $plugin_sources

cd $BUILD_DIR
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

if git diff --quiet; then
    echo "No changes to the output on this push; exiting."
    exit 0
fi

git add -A .
git commit -m "Deploy to GitHub Pages: ${SHA} (Travis Build: $TRAVIS_BUILD_NUMBER)"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}

eval `ssh-agent -s`
# Use stdin/stdout instead of key writing to disk
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in "$CWD/.github/deploy_key.enc" -d | ssh-add -

# Now that we're all set up, we can push.
git push --quiet $SSH_REPO $TARGET_BRANCH

echo "Published to GitHub Pages https://$REPO_USER.github.io/$REPO_NAME/"
