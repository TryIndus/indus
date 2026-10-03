# Cognito verification email

Indus uses Cognito signup and password-recovery codes in its own `/auth` screen. The code template is shared by signup confirmation and password recovery. Do not switch Cognito to its built-in confirmation links: they lead to Cognito-hosted pages, while the Indus code screen keeps the user in the application.

The Cognito app client has user-existence protection enabled. Cognito can return simulated code-delivery details for an unknown or disabled account, so a successful resend or recovery callback is not proof that an email was delivered. The browser uses conditional success copy for those paths. Never diagnose delivery by relying on that callback alone.

Cognito's verification template accepts one email body and does not expose a separate plain-text alternative. Keep the HTML readable without images and validate it in common mail clients before enabling the branded sender.

## Enable the branded sender

`enable_branded_cognito_email` defaults to `false` in each Terraform environment. Before changing it, confirm that the environment's SES account in `us-east-1` can send to unverified recipients. SES sandbox accounts cannot deliver signup codes to arbitrary users. Check the current SES plan and sending limits; the Essentials plan has usage charges but no fixed monthly plan fee. Do not enable paid SES add-ons as part of this change.

Set `enable_branded_cognito_email = true` in the target environment's private Terraform variables and review its plan. Terraform creates an SES identity for `domain_name`, publishes the ownership and DKIM DNS records in the existing Route 53 zone, waits for identity verification, then configures the Cognito user pool to send the HTML code template from `Indus <notifications@domain_name>`. Apply through the established infrastructure workflow, staging first. Verify the SES identity and DKIM status after apply.

In staging, complete signup, wrong-code, expired-code, resend, unconfirmed sign-in, and password-reset checks with a real mailbox that is not an SES verified identity. Check delivery time, inbox and spam placement, sender domain, and the email layout in desktop and mobile clients. Confirm Rails accepts the account after verification. Repeat the smoke check in production during an approved deployment window.

## Recovery

If branded delivery fails, disable `enable_branded_cognito_email` through a reviewed Terraform plan and apply. This returns Cognito to its default sender and template without changing existing account states. Users with an unconfirmed account can request a new code from the Indus sign-in screen. Do not manually mark email addresses verified merely to bypass a delivery problem; Rails requires a verified email for API access.
