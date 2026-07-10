# terraform-portfolio

AWS Multi-Account Infrastructure as Code | Terraform

## 目的

本リポジトリは、AWS Certified Solutions Architect - Professional（SAP）で学習した設計思想を、Terraformを用いてInfrastructure as Codeとして再現することを目的とする。
企業で求められる設計・運用を意識し、以下の観点でAWS基盤を段階的に構築する。

- マルチアカウント戦略
- 高可用性
- セキュリティ
- 運用自動化
- IaCによる再現性・変更管理

AWS Organizationsを中心に、ガバナンス・ネットワーク・アプリ基盤・セキュリティ・運用監査まで段階的に実装する。

## アーキテクチャ

```
AWS Organizations
│
├─ Management (sena)
│   ├─ SCP（コスト保護 / ガバナンス）
│   ├─ CloudTrail（Organization Trail）
│   ├─ Config Aggregator
│   ├─ Security Hub
│   └─ GuardDuty
│
├─ Shared OU（将来拡張予定）
│   └─ IAM Identity Center（SSO）
│
└─ Dev OU
    ├─ VPC / ALB / ASG / EC2 / SSM
    ├─ CloudFront / S3 / Route53
    ├─ Lambda Canary Deploy
    └─ SQS / DLQ
```

##　モジュール構成

```
terraform-portfolio/
├── modules/
│   ├── organizations/   # Organizations / OU / SCP
│   ├── vpc/             # VPC / Subnet / IGW / NAT / Route Table
│   ├── security_group/  # ALB / EC2 / VPCEndpoint 用 SG
│   ├── alb/             # ALB / Target Group / Listener
│   ├── ec2/             # Launch Template / ASG / IAM Role
│   ├── ssm/             # VPC Endpoint（SSM）
│   ├── s3/              # S3 / SSE-KMS / Bucket Policy
│   ├── cloudfront/      # CloudFront Distribution / OAC
│   ├── route53/         # Hosted Zone / Health Check / Failover
│   ├── lambda/          # Lambda / Alias / CodeDeploy / CW Alarm
│   ├── sqs/             # SQS / DLQ / Event Source Mapping
│   ├── cloudtrail/      # Organization Trail
│   ├── config/          # Config Recorder / Delivery Channel
│   └── guardduty/       # GuardDuty Detector
└── main.tf              # 全リソースのエントリーポイント
```

## State管理

現状はローカルStateで管理している。実務を想定した改善として以下を今後対応予定。

| 項目 | 現状 | 実務想定 |
|---|---|---|
| Backend | local | S3 Backend |
| バージョニング | なし | S3 Versioning有効 |
| ロック | なし | DynamoDB Lock |

```hcl
# 実務想定のbackend設定（今後対応予定）
terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "portfolio/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```

## バージョン履歴

| バージョン | 内容 | ステータス |
|---|---|---|
| v1.0.0 | Organizations / SCP / IAM Identity Center | ✅ 実装済み |
| v1.1.0 | VPC / ALB / ASG / EC2 / SSM Session Manager | ✅ 実装済み |
| v1.2.0 | CloudFront / S3 / Route53 / KMS / Secrets Manager | ✅ 実装済み |
| v1.3.0 | Lambda Canary Deploy | ✅ 実装済み |
| v1.4.0 | CloudTrail / Config / Security Hub / SCP強化 | ✅ 実装済み |
| v1.5.0 | GuardDuty / Backup | ✅ 実装済み |
| v1.6.0 | SQS / DLQ / Lambda非同期処理 | ✅ 実装済み |
| v2.0.0 | S3 Data Lake / Glue / Athena / Lake Formation | 🔧 実装予定 |

## 検証コスト

個人検証環境のためコストを意識した設計にしている。

| リソース | 月額目安 | 対策 |
|---|---|---|
| NAT Gateway | $32〜/個 | 検証後すぐ `terraform destroy` |
| ALB | $16〜 | 検証後すぐ `terraform destroy` |
| VPC Endpoint | $7〜/個 | 検証後すぐ `terraform destroy` |
| EC2 (t3.micro) | 無料枠内 | そのまま |
| S3 / CloudFront / Lambda | ほぼ無料 | 常時起動 |
| GuardDuty | 30日無料枠 | 無料枠内で完結 |

常時起動リソースはS3・CloudFront・Lambda・SQS・KMSのみに絞り、月額数百円以下で運用している。NAT GatewayやALBは検証時のみ起動し、終了後は即destroyする運用を徹底している。

## 設計思想

### なぜ Organizations？

単一アカウント運用では以下の問題が発生する：
- IAM権限の爆発的増加
- 障害の波及（Blast Radius が大きい）
- コスト可視化の困難
- ガバナンス統制が不可能

Organizationsにより環境ごとの権限境界を確立し、SCPによって組織全体のガードレールを強制適用する。

### なぜ SCP？

IAMポリシーはアカウント管理者の設定変更で意図せず緩む可能性がある。SCPは管理アカウントから強制適用されるため、どのIAMエンティティも例外なく従うガードレールとして機能する。高額サービスの利用禁止やIAMユーザー作成禁止を組織レベルで固定化することで、コスト事故・権限事故を構造的に防止できる。

ルートユーザー制限SCPはDev / Shared OUにのみアタッチしており、Managementアカウントのルートユーザーは意図的に対象外としている。これはOrganizations解約・アカウント閉鎖など、ルートユーザーでしか行えない操作を封じないための設計判断である。

### なぜ Private Subnet？

EC2をPublic Subnetに置くと攻撃面が広がる。本構成ではALBをDMZとして前段に置き、EC2はPrivate Subnetに隔離している。インバウンドはALB経由のみ、運用アクセスはSSM Session Managerに限定し、最小権限とゼロトラストに近い構成をとっている。

### なぜ SSM Session Manager？

踏み台サーバはSSH鍵管理・SG管理・OSパッチ適用・ログ監査の運用コストが高い。SSMはIAM権限のみで接続を制御でき、セッションログもCloudTrailに自動記録されるため鍵管理ゼロ・踏み台不要・証跡自動化を実現できる。

### なぜ CloudFront？

S3を直接公開すると誤公開リスクが高い。CloudFrontを前段に配置しOACによりS3への直接アクセスを完全に遮断する。エッジキャッシュで高速配信も可能でOAI旧方式は非推奨のため採用しない。

### なぜ Canary Deploy？

一括デプロイは障害時の影響範囲が大きい。Canaryでは新バージョンへのトラフィックを10%に限定し、CloudWatch Alarmが閾値超過を検知した時点でCodeDeployが自動的に旧バージョンへ切り戻す。安全な段階的リリースを行うための構成。ALBターゲットグループにはCookieベースのスティッキーセッションを有効化し、デプロイ中も同一ユーザーが同一バージョンにアクセスし続けられるよう設計している。

### なぜ Route53 Failover？

単一ルーティングではALBやアプリの障害時にエラー画面（502等）が露出し、機会損失に直結する。本構成では、PRIMARY（ALB）の異常検知時にSECONDARY（CloudFront + S3静的メンテ画面）へ自動で切り替えるアクティブ/パッシブ構成を採用している。Route53ヘルスチェックのトリガーにより、手動介入なしでユーザーをメンテナンス画面へ安全に誘導する仕組みをIaC化している。

### なぜ IAM Identity Center？

IAMユーザーはアカウントごとに管理が必要で鍵の使い回し・権限肥大化が起きやすい。Identity Centerにより組織全体のアクセスをSSOに統一し、Permission Setで最小権限を制御することで、鍵管理不要のゼロトラストに近いアクセス制御ができる。Identity CenterはTerraform destroy時に依存関係が壊れやすく、実際に本構成でも削除エラーが発生したため、実務と同様にGUI管理としIaC対象外としている。

## アカウント構成

| アカウント | 役割 | 備考 |
|---|---|---|
| sena（Management） | Management Account | Organizations / SCP / 監査基盤 |
| sena2（Dev） | Dev Account | アプリ基盤・検証環境 |
| Shared（将来追加） | Shared Account | Transit Gateway・共通基盤 |

## 構築で直面した問題と解決

### IAM Identity Center の IaC管理断念

Terraform destroyを実行した際、Identity CenterのPermission Setに関連するリソースで削除エラーが発生した。依存関係やTerraform Providerの制約により、stateとの整合を維持したまま管理することが難しかったため、学習環境ではIdentity CenterをIaC対象外とし、GUIで管理する方針とした。

### OrganizationAccountAccessRole の手動作成

既存アカウントをOrganizationsに招待した場合、`OrganizationAccountAccessRole`は自動作成されない。新規作成時のみ自動生成されるため、sena2アカウントに手動でロールを作成し、ManagementアカウントからのAssumeRoleを許可した上でTerraformのprovider設定に組み込んだ。

### assume_role によるプロバイダ分離

当初は単一providerでManagementアカウント側にVPC/EC2/ALB等が作成されてしまっていた。`assume_role`を用いてDev用providerを分離することで、各リソースを正しいアカウントに分散させた。ロールのARN不一致や権限不足によるエラーを都度CLIで確認しながら解決した。

## 今後の改善

### 機能拡張（v2.0.0）

- データレイク基盤の構築：S3 Data Lake / Glue / Athena / Lake Formation を独立した分析アカウントへ集約
- CloudFrontオリジングループによる高速DR化：ALBエラー時にミリ秒単位でS3へフェイルオーバー
- Transit GatewayによるHub-and-Spoke構成への移行
- GitHub Actions CI/CD（fmt / validate / plan / tfsec / checkov）
- S3 BackendとDynamoDB LockによるState管理の実務化

### コスト・運用最適化

- Configのコスト防御：マルチリージョン展開時に`include_global_resource_types = false`を適用
- SQSとLambdaタイムアウトの整合：`visibility_timeout_seconds`をLambdaタイムアウトの6倍以上に設定

### 対応済み

#### ✅ マルチアカウントのプロバイダ分離

`assume_role`を使用してDevアカウント（sena2）の`OrganizationAccountAccessRole`にスイッチし、VPC / EC2 / ALB等のリソースをDevアカウント側に分離済み。

```hcl
provider "aws" {
  alias  = "dev"
  assume_role {
    role_arn = "arn:aws:iam::482178843450:role/OrganizationAccountAccessRole"
  }
}
```

#### ✅ KMS と S3 / CloudFront の結合

- `aws_s3_bucket_server_side_encryption_configuration`によるS3へのKMS適用済み
- KMSキーポリシーへの`cloudfront.amazonaws.com`の`kms:Decrypt`権限付与済み

#### ✅ Canary Deploy スティッキーセッション対応

ALBターゲットグループにCookieベースのスティッキーセッションを有効化。同一ユーザーがデプロイ完了まで同一バージョンにアクセスし続けられる構成に対応済み。

## 学んだこと
・AWSサービスは設計だけでは分からない制約が多く、実際の構築で理解が深まった。
・Terraformではサービス仕様だけでなくProviderの制約も考慮する必要があった。
・設計→構築→エラー解析→改善を繰り返すことで、IaCによるAWS構築の理解を深められた。
