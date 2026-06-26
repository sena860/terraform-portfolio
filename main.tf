terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
# ============================================
# Organizations
# ============================================
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
  ]
   enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}
# ============================================
# OU作成
# ============================================
resource "aws_organizations_organizational_unit" "shared" {
  name      = "Shared"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "dev" {
  name      = "Dev"
  parent_id = aws_organizations_organization.this.roots[0].id
}
# ============================================
# SCP: コスト保護（Root適用）
# ============================================
resource "aws_organizations_policy" "cost_protection" {
  name        = "cost-protection"
  description = "高額サービス・高スペックEC2インスタンスの使用を禁止する"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveServices"
        Effect = "Deny"
        Action = [
          "redshift:*",
          "elasticmapreduce:*",
          "sagemaker:*",
          "es:*",
          "kinesis:*",
          "kafka:*",
          "quicksight:*",
          "rds:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyExpensiveEC2"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringLike = {
            "ec2:InstanceType" = [
              "m*", "c*", "r*", "x*", "p*", "g*", "inf*"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "cost_protection_root" {
  policy_id = aws_organizations_policy.cost_protection.id
  target_id = aws_organizations_organization.this.roots[0].id
}
# ============================================
# SCP: ガバナンス（Shared / Dev OU適用）
# ============================================
resource "aws_organizations_policy" "governance" {
  name        = "governance"
  description = "IAMユーザー作成禁止・ルートユーザー操作禁止"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyIAMUserCreation"
        Effect   = "Deny"
        Action   = ["iam:CreateUser"]
        Resource = "*"
      },
      {
        Sid      = "DenyRootUser"
        Effect   = "Deny"
        Action   = ["*"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "governance_shared" {
  policy_id = aws_organizations_policy.governance.id
  target_id = aws_organizations_organizational_unit.shared.id
}

resource "aws_organizations_policy_attachment" "governance_dev" {
  policy_id = aws_organizations_policy.governance.id
  target_id = aws_organizations_organizational_unit.dev.id
}
# ============================================
# sena2 を Dev OU に移動
# ============================================
resource "aws_organizations_account" "sena2" {
  name      = "sena2"
  email     = "shengcaihui48@gmail.com"
  parent_id = aws_organizations_organizational_unit.dev.id
}
# ============================================
# IAM Identity Center
# ============================================
data "aws_ssoadmin_instances" "this" {}

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "Admin"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_permission_set" "readonly" {
  name             = "ReadOnly"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
