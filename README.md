AWS Multi-Account Infrastructure as Code | Terraform

## 目的

本リポジトリは、企業規模のAWS基盤をTerraformにより再現し、以下の観点で本番運用可能なアーキテクチャを構築することを目的とする。

- マルチアカウント戦略
- 高可用性
- セキュリティ
- 運用自動化
- IaCによる再現性・変更管理

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
| v1.0.0 | Organizations / SCP / IAM Identity Center | ✅ 実装済み |
| v1.1.0 | VPC / ALB / ASG / EC2 / SSM Session Manager | ✅ 実装済み |
| v1.2.0 | CloudFront / S3 / Route53 / KMS / Secrets Manager | ✅ 実装済み |
| v1.3.0 | Lambda Canary Deploy | ✅ 実装済み |
| v1.4.0 | CloudTrail / Config / Security Hub / SCP強化 | ✅ 実装済み |
| v1.5.0 | GuardDuty / Backup | ✅ 実装済み |
| v1.6.0 | SQS / DLQ / Lambda非同期処理 | ✅ 実装済み |
| v2.0.0 | S3 Data Lake / Glue / Athena / Lake Formation | 🔧 実装予定 |

## 設計思想

### なぜ Organizations？

単一アカウント運用では以下の問題が発生する：
- IAM 権限の爆発的増加
- 障害の波及（Blast Radius が大きい）
- コスト可視化の困難
- ガバナンス統制が不可能

Organizationsにより環境ごとの権限境界を確立し、SCPによって組織全体のガードレールを強制適用する。

### なぜ SCP？

IAMポリシーはアカウント管理者が緩める可能性がある。SCPは管理アカウントから強制適用される絶対的な制御のため、どのIAMエンティティも回避できない。高額サービスのDeny・IAM ユーザー作成禁止により、コスト事故・権限事故を構造的に防止する。

### なぜ Private Subnet？

EC2をPublic Subnetに置くと攻撃面が増大する。本構成ではALBをDMZとして配置し、EC2はPrivate Subnetに隔離。インバウンドはALB経由のみ、アクセスはSSM Session Managerのみとすることで最小権限・ゼロトラストに近い構成を実現。

### なぜ SSM Session Manager？

踏み台サーバはSSH鍵管理・SG管理・OS パッチ適用・ログ監査の運用コストが高い。SSMはIAM権限のみで接続を制御でき、セッションログは CloudTrailに自動記録される。鍵管理ゼロ・踏み台不要・証跡自動化を実現。

### なぜ CloudFront？

S3を直接公開すると誤公開リスクが高い。CloudFrontを前段に配置しOACによりS3への直接アクセスを完全遮断。エッジキャッシュで高速配信を実現する。OAI旧方式は非推奨のため採用しない。

### なぜ Canary Deploy？

一括デプロイは障害時の影響範囲が大きい。Canaryでは新バージョンへのトラフィックを10%に限定し、CloudWatch Alarmが閾値超過を検知した時点で CodeDeployが自動的に旧バージョンへ切り戻す。安全な段階的リリースを実現。

### なぜ IAM Identity Center？

IAMユーザーはアカウントごとに管理が必要で鍵の使い回し・権限肥大化が起きやすい。Identity Centerにより組織全体のアクセスをSSOに統一し、Permission Setによる最小権限管理・鍵管理不要のゼロトラストに近いアクセス管理を実現する。

## アカウント構成

| アカウント | 役割 | 備考 |
|---|---|---|
| sena（Management） | Management Account | Organizations / SCP / 監査基盤 |
| sena2（Dev） | Dev Account | アプリ基盤・検証環境 |
| Shared（将来追加） | Shared Account | Transit Gateway・共通基盤 |

## 今後の改善

- v2.0.0: S3 Data Lake / Glue / Athena / Lake Formation
- Transit Gateway による Hub-and-Spoke 構成
- GitHub Actions CI/CD（fmt / validate / plan / tfsec / checkov）
- Security Hub の自動化ルール追加
- IAM Identity Center の Permission Set 最適化