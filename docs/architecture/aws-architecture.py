"""Render from the repository root with diagrams and Graphviz installed."""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.analytics import ManagedStreamingForKafka
from diagrams.aws.compute import ECR, EKS
from diagrams.aws.database import Aurora, ElastiCache, RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import CloudFront, ELB, Route53
from diagrams.aws.security import Cognito, SecretsManager
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github


with Diagram(
    "Indus AWS architecture — staged database access",
    filename="docs/architecture/aws-architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr={
        "pad": "0.6",
        "labelloc": "t",
        "nodesep": "0.8",
        "ranksep": "1.2",
        "splines": "spline",
        "bgcolor": "white",
        "fontname": "Arial",
        "fontsize": "20",
    },
    node_attr={"fontname": "Arial", "fontsize": "12"},
    edge_attr={"fontname": "Arial", "fontsize": "10"},
):
    users = Users("Users\ntryindus.ca")
    github = Github("GitHub Actions\nSeparate infrastructure / app releases")

    with Cluster("AWS account · us-east-1", graph_attr={"margin": "24"}):
        route53 = Route53("Route 53")
        cloudfront = CloudFront("CloudFront\nStatic web + API / stream origins")
        web = S3("React assets")
        cognito = Cognito("Cognito\nBrowser authentication")
        registry = ECR("Scanned, signed\nimmutable images")
        secrets = SecretsManager("Server-only\nruntime secrets")
        artifacts = S3("Research artifacts\nEncrypted audit / export buckets")
        logs = Cloudwatch("Audit + authenticator logs\nOptional API logs\nRejected flows: 10 min")

        with Cluster("VPC · public subnets in 2 AZs"):
            alb = ELB("Application Load Balancer\nHTTPS API + authenticated SSE")

        with Cluster("VPC · private workloads in active AZ"):
            eks = EKS("EKS · production: 2 nodes\nRails API + Rust market data\nSidekiq + outbox / report workers")

        with Cluster("VPC · private managed data services"):
            proxy = RDS("RDS Proxy\nRetained in proxy / prepare-direct\nRemoved only in direct mode")
            aurora = Aurora("Aurora PostgreSQL\nEncrypted, TLS-required, backed up")
            cache = ElastiCache("Valkey\nSidekiq queues")
            kafka = ManagedStreamingForKafka("MSK Serverless\nMarket + report events\nStill required; removal is proposed")

    users >> route53 >> cloudfront
    cloudfront >> Edge(label="Static assets") >> web
    cloudfront >> Edge(label="API / stream") >> alb >> eks
    users >> Edge(label="Sign-in") >> cognito
    github >> Edge(label="Build / scan / publish") >> registry
    registry >> Edge(label="GitOps image digests") >> eks
    eks >> Edge(label="Default proxy mode · TLS") >> proxy >> aurora
    eks >> Edge(label="prepare-direct / direct · TLS", style="dashed", color="#2563eb") >> aurora
    eks >> secrets
    eks >> cache
    eks >> kafka
    eks >> artifacts
    eks >> Edge(label="Application + control-plane logs") >> logs
    aurora >> Edge(label="Database logs") >> logs
