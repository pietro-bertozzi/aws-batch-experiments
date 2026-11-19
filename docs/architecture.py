"""Draws docs/architecture.png. Run: python architecture.py  (needs `pip install diagrams` + Graphviz)."""
import os

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import Batch, EC2, ECR
from diagrams.aws.cost import Budgets
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.onprem.client import User
from diagrams.onprem.container import Docker
from diagrams.onprem.iac import Terraform

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "architecture")

graph_attr = {"fontsize": "20", "pad": "0.5", "nodesep": "0.7", "ranksep": "1.1"}

with Diagram("Experiment platform on AWS", filename=out, outformat="png",
             show=False, direction="LR", graph_attr=graph_attr):

    you = User("You")
    tf = Terraform("Terraform\n(builds everything)")

    with Cluster("Your laptop"):
        push = Docker("push.sh\nbuild image")
        run = User("run.sh\nsubmit job")

    with Cluster("AWS  (eu-north-1)"):
        with Cluster("Long-lived: foundation/"):
            ecr = ECR("ECR\nimages")
            s3 = S3("S3 results\nruns/<exp>/<run>/\noutput + checkpoint")
            logs = Cloudwatch("CloudWatch\nlogs")
            iam = IAMRole("IAM roles\n(job + instance)")
            budget = Budgets("Budget alerts\n$1 ... $200")

        with Cluster("Free when idle: compute/"):
            batch = Batch("AWS Batch\nqueues: spot / on-demand")
            with Cluster("Default VPC, public subnets"):
                ec2 = EC2("EC2 machines\nstart on demand,\nstop when idle\n(runs your container\n+ exp-wrapper)")

    you >> run
    you >> push
    push >> Edge(label="docker push") >> ecr
    run >> Edge(label="submit job") >> batch
    batch >> Edge(label="starts / stops\n(Spot or on-demand)") >> ec2
    ecr >> Edge(label="pull image") >> ec2
    ec2 >> Edge(label="restore + sync every 2 min\n(checkpoints, results)") >> s3
    ec2 >> Edge(label="stdout") >> logs
    iam - Edge(style="dashed", color="gray") - ec2
    tf >> Edge(style="dotted", label="creates") >> batch
