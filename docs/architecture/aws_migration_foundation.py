from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.database import Aurora, RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import CloudFront, ELB, Route53
from diagrams.aws.security import Cognito, SecretsManager
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github


with Diagram(
    "Indus AWS migration foundation",
    filename="docs/architecture/aws-migration-foundation",
    outformat=["png", "svg"],
    show=False,
    direction="TB",
    graph_attr={"pad": "0.5", "nodesep": "0.6", "ranksep": "0.8", "bgcolor": "white"},
):
    users = Users("Users")
    github = Github("GitHub Actions")
    route53 = Route53("Route 53")
    cloudfront = CloudFront("CloudFront")

    with Cluster("AWS account · us-east-1"):
        with Cluster("Public subnets · two AZs"):
            alb = ELB("Application Load Balancer")

        with Cluster("Private subnets · active workload AZ"):
            eks = EKS("EKS migration workloads")
            secrets = SecretsManager("Runtime and migration secrets")

        with Cluster("Private data boundary · two AZs"):
            aurora = Aurora("Aurora PostgreSQL")
            proxy = RDS("RDS Proxy")
            cognito = Cognito("Cognito user pool")
            exports = S3("Encrypted export and audit buckets")
            logs = Cloudwatch("Database and application logs")

    users >> route53 >> cloudfront >> Edge(label="HTTPS") >> alb >> eks
    github >> Edge(label="immutable image and migration job") >> eks
    eks >> Edge(label="TLS") >> proxy >> aurora
    eks >> secrets
    eks >> cognito
    eks >> Edge(label="verified export artifacts") >> exports
    aurora >> logs
