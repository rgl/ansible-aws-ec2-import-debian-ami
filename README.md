# About

[![Lint status](https://github.com/rgl/ansible-aws-ec2-import-debian-ami/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/ansible-aws-ec2-import-debian-ami/actions/workflows/lint.yml)

This shows how to import an existing Debian Linux virtual machine image into an AWS EC2 AMI.

This shows how to:

* Download a disk image.
* Convert the disk image to the Stream-Optimized VMDK format.
* Upload the disk image to an S3 bucket.
* Import the disk image into an AMI.
* Wait for the import to finish.
* Tag the AMI.
* Tag the AMI's EBS snapshot.
* Create a VPC.
* Create a VM (EC2 instance) from the created AMI.
* Destroy the created resources.

# Usage (on a Ubuntu Desktop)

Install the dependencies:

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
* [Docker](https://docs.docker.com/engine/install/).

Set the AWS Account credentials using SSO, e.g.:

```bash
# set the account credentials.
# NB the aws cli stores these at ~/.aws/config.
# NB this is equivalent to manually configuring SSO using aws configure sso.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-manual
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
cat >secrets-example.sh <<'EOF'
# set the environment variables to use a specific profile.
# NB use aws configure sso to configure these manually.
# e.g. use the pattern <aws-sso-session>-<aws-account-id>-<aws-role-name>
export aws_sso_session='example'
export aws_sso_start_url='https://example.awsapps.com/start'
export aws_sso_region='eu-west-1'
export aws_sso_account_id='123456'
export aws_sso_role_name='AdministratorAccess'
export AWS_PROFILE="$aws_sso_session-$aws_sso_account_id-$aws_sso_role_name"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# configure the ~/.aws/config file.
# NB unfortunately, I did not find a way to create the [sso-session] section
#    inside the ~/.aws/config file using the aws cli. so, instead, manage that
#    file using python.
python3 <<'PY_EOF'
import configparser
import os
aws_sso_session = os.getenv('aws_sso_session')
aws_sso_start_url = os.getenv('aws_sso_start_url')
aws_sso_region = os.getenv('aws_sso_region')
aws_sso_account_id = os.getenv('aws_sso_account_id')
aws_sso_role_name = os.getenv('aws_sso_role_name')
aws_profile = os.getenv('AWS_PROFILE')
config = configparser.ConfigParser()
aws_config_directory_path = os.path.expanduser('~/.aws')
aws_config_path = os.path.join(aws_config_directory_path, 'config')
if os.path.exists(aws_config_path):
  config.read(aws_config_path)
config[f'sso-session {aws_sso_session}'] = {
  'sso_start_url': aws_sso_start_url,
  'sso_region': aws_sso_region,
  'sso_registration_scopes': 'sso:account:access',
}
config[f'profile {aws_profile}'] = {
  'sso_session': aws_sso_session,
  'sso_account_id': aws_sso_account_id,
  'sso_role_name': aws_sso_role_name,
  'region': aws_sso_region,
}
os.makedirs(aws_config_directory_path, mode=0o700, exist_ok=True)
with open(aws_config_path, 'w') as f:
  config.write(f)
PY_EOF
unset aws_sso_start_url
unset aws_sso_region
unset aws_sso_session
unset aws_sso_account_id
unset aws_sso_role_name
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login
fi
aws sts get-caller-identity
EOF
```

Or, set the AWS Account credentials using an Access Key, e.g.:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
cat >secrets-example.sh <<'EOF'
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
unset AWS_PROFILE
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
EOF
```

Load the secrets:

```bash
source secrets-example.sh
```

Review the files:

* [`ami-create.yml` playbook](ami-create.yml).
* [`ami-destroy.yml` playbook](ami-destroy.yml).
* [`ami-test-create.yml` playbook](ami-test-create.yml).
* [`ami-test-destroy.yml` playbook](ami-test-destroy.yml).

Lint the playbooks:

```bash
./ansible-lint.sh --offline --parseable ami-create.yml
./ansible-lint.sh --offline --parseable ami-destroy.yml
./ansible-lint.sh --offline --parseable ami-test-create.yml
./ansible-lint.sh --offline --parseable ami-test-destroy.yml
```

Create the AMI:

```bash
./ansible-playbook.sh ami-create.yml | tee ansible.log
```

In another shell, you can watch the progress using:

```bash
source secrets-example.sh
watch "aws ec2 describe-import-image-tasks | jq '.ImportImageTasks[0]'"
```

Use the created AMI to create a new EC2 instance:

```bash
./ansible-playbook.sh ami-test-create.yml | tee ansible.log
```

Login into the EC2 instance:

```bash
public_ip_address="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=rgl-ansible-aws-ec2-import-debian-ami" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text)"
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "admin@$public_ip_address"
```

Using your ssh client, and [aws ssm session manager to proxy the ssh connection](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html), open a shell inside the VM and execute some commands:

```bash
instance_id="$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=rgl-ansible-aws-ec2-import-debian-ami" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)"
ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ProxyCommand='aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p' \
  "admin@$instance_id"
cat /etc/os-release
id
ps -efww --forest
sudo ps -efww --forest
exit
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `sh` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a sh shell. to switch to a different one,
#    see the next example.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell.
#    NB that document is created in our account when session manager is used
#       for the first time.
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-default-session-document.html
# see aws ssm describe-document --name SSM-SessionManagerRunShell
aws ssm start-session --target "$instance_id"
echo $SHELL
id
sudo id
ps -efww --forest
sudo ps -efww --forest
exit
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `bash` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a sh shell, but we immediately switch to
#    the bash shell.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell which
#    is created in our account when session manager is used the first time.
# see aws ssm describe-document --name AWS-StartInteractiveCommand --query 'Document.Parameters[*]'
# see aws ssm describe-document --name AWS-StartNonInteractiveCommand --query 'Document.Parameters[*]'
aws ssm start-session \
  --document-name AWS-StartInteractiveCommand \
  --parameters '{"command":["exec env SHELL=$(which bash) bash -il"]}' \
  --target "$instance_id"
echo $SHELL
id
sudo id
ps -efww --forest
sudo ps -efww --forest
exit
```

When you are done, destroy everything:

```bash
./ansible-playbook.sh ami-test-destroy.yml | tee ansible.log
./ansible-playbook.sh ami-destroy.yml | tee ansible.log
```

List this repository dependencies (and which have newer versions):

```bash
export GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN'
./renovate.sh
```
