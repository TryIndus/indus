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
    "Indus AWS architecture",
    filename="docs/architecture/aws-architecture",
    outformat=["png", "svg"],
    show=False,
    direction="LR",
    graph_attr={
        "pad": "1.4",
        "nodesep": "1.3",
        "ranksep": "1.8",
        "splines": "ortho",
        "bgcolor": "white",
        "fontname": "Arial",
        "fontsize": "20",
    },
    node_attr={"fontname": "Arial", "fontsize": "14"},
    edge_attr={"fontname": "Arial", "fontsize": "12"},
):
    users = Users("Users")
    github = Github("GitHub Actions")
    route53 = Route53("Route 53")
    cloudfront = CloudFront("CloudFront")

    with Cluster("AWS account · us-east-1", graph_attr={"margin": "32", "pad": "0.8"}):
        with Cluster("Public subnets · two AZs", graph_attr={"margin": "28", "pad": "0.6"}):
            alb = ELB("Application Load Balancer")

        with Cluster("Private subnets · active workload AZ", graph_attr={"margin": "28", "pad": "0.6"}):
            eks = EKS("EKS workloads")
            secrets = SecretsManager("Runtime secrets")

        with Cluster("Private data boundary · two AZs", graph_attr={"margin": "28", "pad": "0.6"}):
            aurora = Aurora("Aurora PostgreSQL")
            proxy = RDS("RDS Proxy")
            cognito = Cognito("Cognito user pool")
            exports = S3("Encrypted export and audit buckets")
            logs = Cloudwatch("Database and application logs")

    users >> route53 >> cloudfront >> Edge(label="HTTPS") >> alb >> eks
    github >> Edge(label="immutable image and data job") >> eks
    eks >> Edge(label="TLS") >> proxy >> aurora
    eks >> secrets
    eks >> cognito
    eks >> Edge(label="verified export artifacts") >> exports
    aurora >> logs
