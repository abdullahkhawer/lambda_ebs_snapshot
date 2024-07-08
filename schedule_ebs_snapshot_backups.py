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
import collections
import datetime
import boto3

def lambda_handler(event, context): # pylint: disable=unused-argument
    """
    This function creates snapshots of AWS EBS volumes attached to AWS EC2 instances
    that have a "Backup" tag containing either 'true', 'yes', or '1'.
    This function should be run at least daily.
    """
    ec2_client = boto3.client('ec2')

    reservations = ec2_client.describe_instances(
        Filters=[
            {'Name': 'tag:Backup', 'Values': ['true', 'yes', '1']},
        ]
    ).get(
        'Reservations', []
    )

    instances = [
        instance for reservation in reservations for instance in reservation['Instances']
    ]

    print(f"Found {str(len(instances))} instances that need backing up")

    to_tag = collections.defaultdict(list)

    for instance in instances:
        try:
            retention_days = [
                int(t.get('Value')) for t in instance['Tags']
                if t['Key'] == 'Retention'][0]
        except IndexError:
            retention_days = 7

        for dev in instance['BlockDeviceMappings']:
            if dev.get('Ebs', None) is None:
                continue
            vol_id = dev['Ebs']['VolumeId']
            print(f"Found EBS volume {vol_id} on instance {instance['InstanceId']}")

            snap = ec2_client.create_snapshot(
                VolumeId=vol_id,
            )

            to_tag[retention_days].append(snap['SnapshotId'])

            print(
                f"Retaining snapshot {snap['SnapshotId']} of volume {vol_id} "
                f"from instance {instance['InstanceId']} for {str(retention_days)} days"
            )

    for retention_days in to_tag.keys(): # pylint: disable=consider-using-dict-items
        delete_date = datetime.date.today() + datetime.timedelta(days=retention_days)
        delete_fmt = delete_date.strftime('%Y-%m-%d')
        print(f"Will delete {str(len(to_tag[retention_days]))} snapshots on {delete_fmt}")
        ec2_client.create_tags(
            Resources=to_tag[retention_days],
            Tags=[
                {'Key': 'DeleteOn', 'Value': delete_fmt},
            ]
        )
