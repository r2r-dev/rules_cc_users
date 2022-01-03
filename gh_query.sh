#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq github-cli fzf

GH_TOKEN_TXT_FILE=$1
REPO_LIST_FILE=$2

GH_TOKEN="$(cat $GH_TOKEN_TXT_FILE)"

gh auth login --with-token < ${GH_TOKEN_TXT_FILE}

while read -r repo; do
        echo $repo >/dev/stderr
        gh repo view $repo --json "stargazerCount,description,forkCount,nameWithOwner,url,issues,defaultBranchRef"
done < ${REPO_LIST_FILE} \
 | jq -r '. | {"description":.description, "forks":.forkCount, "issues":.issues.totalCount, "stars":.stargazerCount, "url":.url, "name":.nameWithOwner, "branch":.defaultBranchRef.name}' \
 | jq -s . \
 | jq -r '. | (map(keys) | add | unique) as $cols | map(. as $row | $cols | map($row[.])) as $rows | $cols, $rows[] | @csv' > results.csv

while read -r repo_details; do
  branch=$(echo $repo_details | cut -d'"' -f2)
  name=$(echo $repo_details | rev | cut -d '"' -f4 | rev)
  echo "processing ${repo_details}"
  mkdir -p "repos/${name}" || true
  curl -X GET -u $GH_TOKEN:x-oauth-basic -s "https://api.github.com/repos/${name}/git/trees/${branch}?recursive=1" | jq -r '.tree[].path' | sed 's/^/\.\//' | awk -F'/' '{
        depth=100;
        offset=2;
        str="|  ";
        path="";
        if(NF >= 2 && NF < depth + offset) {
                while(offset < NF) {
                        path = path "|  ";
                        offset ++;
                }
                print path "|-- "$NF;
        }
  }' > "repos/${name}/tree.txt"
  head -n 1 results.csv > "repos/${name}/repo.txt"
  echo "${repo_details}" >> "repos/${name}/repo.txt"
  # avoid hitting ratelimiter
  sleep 2

done <<< $(tail -n +2 results.csv)

sed -e '1 s|$|,"md5sum"|' results.csv | head -n 1 > results_md5.csv
while read -r line; do
  echo "${line},\"$(echo $line | rev | cut -d '"' -f4 | rev | head | xargs -I {} md5sum repos/{}/tree.txt | cut -d' ' -f1)\""

done <<< $(tail -n +2 results.csv) >> results_md5.csv

# Preview with sq + fzf
# https://github.com/neilotoole/sq/
#./sq sql \
#  "SELECT name, MAX(stars) as stars, forks, issues, description FROM data GROUP BY md5sum ORDER BY stars desc" \
#  --opts header=true <<< $(cat results_md5.csv) \
#  | tail -n +2 \
#  | fzf --preview='cat repos/{1}/tree.txt' --bind k:preview-up,j:preview-down
