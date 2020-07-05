#!/bin/zsh -e
SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ ! "$BRANCH" = "master" ]; then
	printf >&2 "\033[1;31mNot on master branch, abording\033[0m"
	exit -1
fi

# if  [[ -n $(git status --porcelain) ]]; then
#   printf >&2 "\033[1;31mCannot release version because there are unstaged changes, aborting\nChanges:\033[0m\n"
#   git status --short
#   exit -1
# fi
#
# if [[ -n $(git log --branches --not --remotes) ]]; then
#   echo -e "\033[1;34mPushing pending commits to git\033[0m"
#   git push
# fi

echo -e "\033[1;34mCreating release notes\033[0m"

RELEASE_NOTES_FILE="${SCRIPTPATH}/Distribution/_tmp_release_notes.md"

# rm -f "${RELEASE_NOTES_FILE}"
touch "${RELEASE_NOTES_FILE}"
open -Wn "${RELEASE_NOTES_FILE}"

if ! [ -s "${RELEASE_NOTES_FILE}" ]; then
	echo -e >&2 "\033[1;31mNo release notes provided, aborting\033[0m"
	rm -f "${RELEASE_NOTES_FILE}"
	exit -1
fi

${SCRIPTPATH}/Scripts/updateCopyright.sh

# rm -fr "${SCRIPTPATH}/Build"
rm -fr "${SCRIPTPATH}/Distribution/DetoxRecorder.framework"
rm -f "${SCRIPTPATH}/Distribution/DetoxRecorderCLI"

echo -e "\033[1;34mBuilding DetoxRecorder.framework\033[0m"

xcodebuild -project "${SCRIPTPATH}/DetoxRecorder/DetoxRecorder.xcodeproj" build -configuration Release -scheme DetoxRecorderFramework -derivedDataPath "${SCRIPTPATH}/Build" -quiet
cp -R "${SCRIPTPATH}/Build/Build/Products/Release-universal/DetoxRecorder.framework" "${SCRIPTPATH}/Distribution"

echo -e "\033[1;34mBuilding Detox Recorder CLI\033[0m"

xcodebuild -project "${SCRIPTPATH}/DetoxRecorder/DetoxRecorder.xcodeproj" build -configuration Release -scheme DetoxRecorderCLI -sdk macosx -derivedDataPath "${SCRIPTPATH}/Build" -quiet
cp "${SCRIPTPATH}/Build/Build/Products/Release/DetoxRecorderCLI" "${SCRIPTPATH}/Distribution"

echo -e "\033[1;34mCopying script\033[0m"
cp "${SCRIPTPATH}/record.sh" "${SCRIPTPATH}/Distribution"

echo -e "\033[1;34mUpdating package.json version\033[0m"
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${SCRIPTPATH}/Distribution/DetoxRecorder.framework/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${SCRIPTPATH}/Distribution/DetoxRecorder.framework/Info.plist")

VERSION="${SHORT_VERSION}"."${BUILD_NUMBER}"

cd "${SCRIPTPATH}/Distribution"
npm version "${VERSION}" --allow-same-version

# echo -e "\033[1;34mReleasing\033[0m"
# npm publish

git add -A &> /dev/null
git commit -m "${VERSION}" &> /dev/null
git push

#Escape user input in markdown to valid JSON string using PHP 🤦‍♂️ (https://stackoverflow.com/a/13466143/983912)
RELEASENOTESCONTENTS=$(printf '%s' "$(<"${RELEASE_NOTES_FILE}")" | php -r 'echo json_encode(file_get_contents("php://stdin"));')

echo -e "\033[1;34mCreating GitHub release\033[0m"

API_JSON=$(printf '{"tag_name": "%s","target_commitish": "master", "name": "v%s", "body": %s, "draft": false, "prerelease": false}' "$VERSION" "$VERSION" "$RELEASENOTESCONTENTS")
curl -H "Authorization: token ${GITHUB_RELEASES_TOKEN}" -s --data "$API_JSON" https://api.github.com/repos/wix/DetoxRecorder/releases

rm -f "${RELEASE_NOTES_FILE}"