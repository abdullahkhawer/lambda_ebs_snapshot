# Copyright 2015 Ryan S Brown
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# pylint: disable=missing-module-docstring
import re
import datetime
import boto3

def lambda_handler(event, context): # pylint: disable=unused-argument
    """
    This function looks at all the snapshots of AWS EBS volumes that have a 
    "DeleteOn" tag containing the current day formatted as YYYY-MM-DD. 
    This function should be run at least daily.
    """
    account_ids = []

    ec2_client = boto3.client('ec2')
    iam_client = boto3.client('iam')

    try:
        """
        You can replace this try/except by filling in `account_ids` yourself.
        Get your account ID with:
        > import boto3
        > iam = boto3.client('iam')
        > print iam.get_user()['User']['Arn'].split(':')[4]
        """
        iam_client.get_user()
    except Exception as exception: # pylint: disable=broad-except
        # use the exception message to get the account ID the function executes under
        account_ids.append(re.search(r'(arn:aws:sts::)([0-9]+)', str(exception)).groups()[1])

    delete_on = datetime.date.today().strftime('%Y-%m-%d')
    filters = [
        {'Name': 'tag-key', 'Values': ['DeleteOn']},
        {'Name': 'tag-value', 'Values': [delete_on]},
    ]
    snapshot_response = ec2_client.describe_snapshots(OwnerIds=account_ids, Filters=filters)

    for snapshot in snapshot_response['Snapshots']:
        snapshot_id = snapshot['SnapshotId']
        print(f"Deleting snapshot {snapshot_id}")
        ec2_client.delete_snapshot(SnapshotId=snapshot_id)
