# Cognito verification email

Indus uses Cognito signup and password-recovery codes in its own `/auth` screen. The code template is shared by signup confirmation and password recovery. Do not switch Cognito to its built-in confirmation links: they lead to Cognito-hosted pages, while the Indus code screen keeps the user in the application.

The Cognito app client has user-existence protection enabled. Cognito can return simulated code-delivery details for an unknown or disabled account, so a successful resend or recovery callback is not proof that an email was delivered. The browser uses conditional success copy for those paths. Never diagnose delivery by relying on that callback alone.

Cognito's verification template accepts one email body and does not expose a separate plain-text alternative. Keep the HTML readable without images and validate it in common mail clients before enabling the branded sender.

## Enable the branded sender

`enable_branded_cognito_email` defaults to `false` in Terraform, but the optimized production profile sets it to `true` in its tracked `production-email.auto.tfvars`. Terraform loads that file after the private `terraform.tfvars`, including in the GitHub infrastructure workflow. Before applying, confirm that the environment's SES account in `us-east-1` can send to unverified recipients. SES sandbox accounts cannot deliver signup codes to arbitrary users. Check the current SES plan and sending limits; the Essentials plan has usage charges but no fixed monthly plan fee. Do not enable paid SES add-ons as part of this change.

Update the optimized bootstrap Terraform role before running the environment workflow. Dispatch `prepare-email` on `main` and review its saved plan. It creates the SES identity for `tryindus.ca` and publishes ownership, DKIM, monitoring-only DMARC, and custom MAIL FROM DNS records in the existing public Route 53 zone without changing Cognito. Verify the identity, DKIM, and MAIL FROM status with `aws ses get-identity-verification-attributes --identities tryindus.ca --region us-east-1`, `aws ses get-identity-dkim-attributes --identities tryindus.ca --region us-east-1`, and `aws ses get-identity-mail-from-domain-attributes --identities tryindus.ca --region us-east-1`. The MAIL FROM subdomain `bounce.tryindus.ca` gives SES an SPF-aligned Return-Path once verified.

Request SES production access in `us-east-1` with the verified domain, then check `aws sesv2 get-account --region us-east-1 --query ProductionAccessEnabled --output text` returns `True`. Dispatch the full `apply` and review its saved plan. Its preflight refuses to switch Cognito until production access, DKIM, and MAIL FROM all show success. The pool then sends the HTML code template from `Indus <notifications@tryindus.ca>`.

After deployment, complete signup, wrong-code, expired-code, resend, unconfirmed sign-in, and password-reset checks with a real mailbox that is not an SES verified identity. Check delivery time, inbox and spam placement, sender domain, and the email layout in desktop and mobile clients. Inspect the received message headers: SPF should pass for `bounce.tryindus.ca`, DKIM should pass for `tryindus.ca`, and DMARC should pass for the visible From domain. Confirm Rails accepts the account after verification. Authentication improves deliverability but does not guarantee inbox placement; use recipient feedback and reputation data to investigate any remaining spam classification.

## Recovery

If branded delivery fails, set `enable_branded_cognito_email = false` in `production-email.auto.tfvars`, review the plan, and apply through the optimized workflow. Changing the private `terraform.tfvars` alone will not override the tracked auto file. This returns Cognito to its default sender and template without changing existing account states. Users with an unconfirmed account can request a new code from the Indus sign-in screen. Do not manually mark email addresses verified merely to bypass a delivery problem; Rails requires a verified email for API access.
