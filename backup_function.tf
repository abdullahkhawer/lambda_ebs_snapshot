resource "aws_iam_role" "ebs_backup_role" {
  name = "ebs_backup_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ebs_backup_policy" {
  name = "ebs_backup_policy"
  role = aws_iam_role.ebs_backup_role.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "logs:CreateLogStream",
              "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": "ec2:Describe*",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot",
                "ec2:CreateTags",
                "ec2:ModifySnapshotAttribute",
                "ec2:ResetSnapshotAttribute"
            ],
            "Resource": ["*"]
        }
    ]
}
EOF
}

resource "aws_cloudwatch_log_group" "schedule_ebs_snapshot_backups" {
  name              = "/aws/lambda/schedule_ebs_snapshot_backups"
  retention_in_days = 14
}

data "archive_file" "schedule_ebs_snapshot_backups_zip" {
  type        = "zip"
  source_file = "${path.module}/schedule_ebs_snapshot_backups.py"
  output_path = "${path.module}/schedule_ebs_snapshot_backups.zip"
}

resource "aws_lambda_function" "schedule_ebs_snapshot_backups" {
  filename         = "${path.module}/schedule_ebs_snapshot_backups.zip"
  function_name    = "schedule_ebs_snapshot_backups"
  description      = "Automatically backs up instances tagged with backup: true"
  role             = aws_iam_role.ebs_backup_role.arn
  timeout          = 60
  handler          = "schedule_ebs_snapshot_backups.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.schedule_ebs_snapshot_backups_zip.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.schedule_ebs_snapshot_backups.name
  }
}

resource "aws_cloudwatch_log_group" "ebs_snapshot_janitor" {
  name              = "/aws/lambda/ebs_snapshot_janitor"
  retention_in_days = 14
}

data "archive_file" "ebs_snapshot_janitor_zip" {
  type        = "zip"
  source_file = "${path.module}/ebs_snapshot_janitor.py"
  output_path = "${path.module}/ebs_snapshot_janitor.zip"
}

resource "aws_lambda_function" "ebs_snapshot_janitor" {
  filename         = "${path.module}/ebs_snapshot_janitor.zip"
  function_name    = "ebs_snapshot_janitor"
  description      = "Cleans up old EBS backups"
  role             = aws_iam_role.ebs_backup_role.arn
  timeout          = 60
  handler          = "ebs_snapshot_janitor.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.ebs_snapshot_janitor_zip.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.ebs_snapshot_janitor.name
  }
}

resource "aws_cloudwatch_event_rule" "schedule_ebs_snapshot_backups" {
  name                = "schedule_ebs_snapshot_backups"
  description         = "Schedule for ebs snapshot backups"
  schedule_expression = var.ebs_snapshot_backups_schedule
}

resource "aws_cloudwatch_event_rule" "schedule_ebs_snapshot_janitor" {
  name                = "schedule_ebs_snapshot_janitor"
  description         = "Schedule for ebs snapshot janitor"
  schedule_expression = var.ebs_snapshot_janitor_schedule
}

resource "aws_cloudwatch_event_target" "schedule_ebs_snapshot_backups" {
  rule      = aws_cloudwatch_event_rule.schedule_ebs_snapshot_backups.name
  target_id = "schedule_ebs_snapshot_backups"
  arn       = aws_lambda_function.schedule_ebs_snapshot_backups.arn
}

resource "aws_cloudwatch_event_target" "schedule_ebs_snapshot_janitor" {
  rule      = aws_cloudwatch_event_rule.schedule_ebs_snapshot_janitor.name
  target_id = "ebs_snapshot_janitor"
  arn       = aws_lambda_function.ebs_snapshot_janitor.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_backup" {
  statement_id  = "AllowExecutionFromCloudWatch_schedule_ebs_snapshot_backups"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.schedule_ebs_snapshot_backups.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule_ebs_snapshot_backups.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_janitor" {
  statement_id  = "AllowExecutionFromCloudWatch_ebs_snapshot_janitor"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_snapshot_janitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule_ebs_snapshot_janitor.arn
}
