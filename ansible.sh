#!/bin/bash
set -euo pipefail

command="$(basename "$0" .sh)"

# build the ansible image.
install -d tmp
DOCKER_BUILDKIT=1 docker build -f Dockerfile.ansible --iidfile tmp/ansible-iid.txt .
ansible_iid="$(cat tmp/ansible-iid.txt)"

# show information about the execution environment.
docker run --rm -i "$ansible_iid" bash <<'EOF'
exec 2>&1
set -euxo pipefail
cat /etc/os-release
ansible --version
python3 -m pip list
ansible-galaxy collection list
EOF

# execute command (e.g. ansible-playbook).
# NB the GITHUB_ prefixed environment variables are used to trigger ansible-lint
#    to annotate the GitHub Actions Workflow with the linting violations.
#    see https://github.com/ansible/ansible-lint/blob/v25.6.1/src/ansiblelint/app.py#L106-L111
#    see https://ansible-lint.readthedocs.io/en/latest/usage/#ci-cd
exec docker run \
    --rm \
    --net=host \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$HOME/.ssh:/tmp/.ssh:ro" \
    -v "$HOME/.aws:/tmp/.aws" \
    -v "$PWD:/project" \
    -w /project \
    -e AWS_PROFILE \
    -e GITHUB_ACTIONS \
    -e GITHUB_WORKFLOW \
    "$ansible_iid" \
    "$command" \
    "$@"
