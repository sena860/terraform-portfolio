AWS Multi-Account Infrastructure as Code | Terraform

## 目的

本リポジトリは、AWS Certified Solutions Architect - Professional（SAP）で学習した設計思想を、Terraformを用いてInfrastructure as Codeとして再現することを目的とする。
企業で求められる設計・運用を意識し、以下の観点でAWS基盤を段階的に構築する。

マルチアカウント戦略
高可用性
セキュリティ
運用自動化
IaCによる再現性・変更管理

AWS Organizationsを中心に、ガバナンス・ネットワーク・アプリ基盤・セキュリティ・運用監査まで段階的に実装する。

## アーキテクチャ
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

## バージョン履歴

| バージョン | 内容 | ステータス |
|---|---|---|
| v1.0.0 | Organizations / SCP / IAM Identity Center | 実装済み |
| v1.1.0 | VPC / ALB / ASG / EC2 / SSM Session Manager | 実装済み |
| v1.2.0 | CloudFront / S3 / Route53 / KMS / Secrets Manager | 実装済み |
| v1.3.0 | Lambda Canary Deploy | 実装済み |
| v1.4.0 | CloudTrail / Config / Security Hub / SCP強化 | 実装済み |
| v1.5.0 | GuardDuty / Backup | 実装済み |
| v1.6.0 | SQS / DLQ / Lambda非同期処理 | 実装済み |
| v2.0.0 | S3 Data Lake / Glue / Athena / Lake Formation | 実装予定 |

## 設計思想

### なぜ Organizations？

単一アカウント運用では以下の問題が発生する：
- IAM 権限の爆発的増加
- 障害の波及（Blast Radius が大きい）
- コスト可視化の困難
- ガバナンス統制が不可能

Organizationsにより環境ごとの権限境界を確立し、SCPによって組織全体のガードレールを強制適用する。

### なぜ SCP？

IAMポリシーはアカウント管理者の設定変更で意図せず緩む可能性がある。
SCPは管理アカウントから強制適用されるため、
どのIAMエンティティも例外なく従うガードレールとして機能する。
高額サービスの利用禁止やIAMユーザー作成禁止を組織レベルで固定化することで、
コスト事故・権限事故を構造的に防止できる。

### なぜ Private Subnet？

EC2をPublic Subnetに置くと攻撃面が広がる。本構成ではALBをDMZとして前段に置き、EC2はPrivate Subnetに隔離している。インバウンドはALB経由のみ、運用アクセスはSSM Session Managerに限定し、最小権限とゼロトラストに近い構成をとっている。

### なぜ SSM Session Manager？

踏み台サーバはSSH鍵管理・SG管理・OS パッチ適用・ログ監査の運用コストが高い。SSMはIAM権限のみで接続を制御でき、セッションログもCloudTrailに自動記録されるため鍵管理ゼロ・踏み台不要・証跡自動化を実現できる。

### なぜ CloudFront？

S3を直接公開すると誤公開リスクが高い。CloudFrontを前段に配置しOACによりS3への直接アクセスを完全に遮断する。エッジキャッシュで高速配信も可能でOAI旧方式は非推奨のため採用しない。

### なぜ Canary Deploy？

一括デプロイは障害時の影響範囲が大きい。Canaryでは新バージョンへのトラフィックを10%に限定し、CloudWatch Alarmが閾値超過を検知した時点で CodeDeployが自動的に旧バージョンへ切り戻す。安全な段階的リリースを行うための構成。

### なぜ IAM Identity Center？

IAMユーザーはアカウントごとに管理が必要で鍵の使い回し・権限肥大化が起きやすい。Identity Centerにより組織全体のアクセスをSSOに統一し、Permission Setで最小権限を制御することで、鍵管理不要のゼロトラストに近いアクセス制御ができる。
Identity CenterはTerraform destroy時に依存関係が壊れやすく、実際に本構成でも削除エラーが発生したため、実務と同様にGUI管理としIaC対象外としている。


## アカウント構成

| アカウント | 役割 | 備考 |
|---|---|---|
| sena（Management） | Management Account | Organizations / SCP / 監査基盤 |
| sena2（Dev） | Dev Account | アプリ基盤・検証環境 |
| Shared（将来追加） | Shared Account | Transit Gateway・共通基盤 |

## 今後の改善

### 機能追加

- v2.0.0: S3 Data Lake / Glue / Athena / Lake Formation
- Transit Gateway による Hub-and-Spoke 構成
- GitHub Actions CI/CD（fmt / validate / plan / tfsec / checkov）
- Canary Deploy の改善：ALB ターゲットグループのスティッキーセッション（Cookie ベース）を有効化し、同一ユーザーがデプロイ完了まで同一バージョンにアクセスし続けられる構成に改善予定

### 修正・改善

#### マルチアカウントのプロバイダ分離

現状は `provider "aws"` が1つのみのため、VPC / EC2 / ALB 等のリソースが Management アカウント（sena）側に作成されている。本来は `assume_role` を使用して Dev アカウント（sena2）の `OrganizationAccountAccessRole` にスイッチし、リソースをアカウントごとに分離すべき。

```hcl
provider "aws" {
  alias  = "dev"
  assume_role {
    role_arn = "arn:aws:iam::482178843450:role/OrganizationAccountAccessRole"
  }
}
```

個人検証環境のため現状は単一プロバイダで構築しているが、今後のバージョンで対応予定。

#### KMS と S3 / CloudFront の結合

`aws_kms_key.s3` を作成しているが、以下の設定が未完了。

- `aws_s3_bucket_server_side_encryption_configuration` による S3 への KMS 適用
- KMS キーポリシーへの `cloudfront.amazonaws.com` の `kms:Decrypt` 権限付与

後者がないと CloudFront が KMS 暗号化された S3 からオブジェクトを取得できず 403 エラーになる。今後のバージョンで対応予定。
