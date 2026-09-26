moved {
  from = aws_security_group.rds_proxy
  to   = aws_security_group.rds_proxy[0]
}

moved {
  from = aws_security_group_rule.proxy_from_cluster
  to   = aws_security_group_rule.proxy_from_cluster[0]
}

moved {
  from = aws_security_group_rule.database_from_proxy
  to   = aws_security_group_rule.database_from_proxy[0]
}

moved {
  from = aws_security_group_rule.proxy_to_database
  to   = aws_security_group_rule.proxy_to_database[0]
}

moved {
  from = aws_iam_role.rds_proxy
  to   = aws_iam_role.rds_proxy[0]
}

moved {
  from = aws_iam_role_policy.rds_proxy
  to   = aws_iam_role_policy.rds_proxy[0]
}

moved {
  from = aws_db_proxy.data
  to   = aws_db_proxy.data[0]
}

moved {
  from = aws_db_proxy_default_target_group.data
  to   = aws_db_proxy_default_target_group.data[0]
}

moved {
  from = aws_db_proxy_target.data
  to   = aws_db_proxy_target.data[0]
}

