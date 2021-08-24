---
page_type: sample
products:
- Power Apps
- Microsoft Azure Logic Apps
- SharePoint
- Azure Key Vault
- Microsoft Teams
description: Power Apps solution that automates the guest approval and invite process
urlFragment: microsoft-teams-apps-request-a-guest
---

# Request-a-guest App Template

| [Documentation](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Home) | [Deployment guide](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Deployment-Guide) | [Architecture](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Architecture) | [Cost Estimates](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Cost-Estimates) | [Data Retention](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Data-Retention)
| ---- | ---- | ---- | ---- | ---- |

Many organisations have a requirement to control guest access into their Azure AD tenant. This can be achieved by locking down guest access within Azure AD so only administrators and those in the guest inviter role can issue invites to external guests. This can also be extended to SharePoint and OneDrive by only allowing sharing with existing guests in the tenant. For more information on controlling external access see:  [Limit Sharing in Microsoft 365](https://docs.microsoft.com/en-us/microsoft-365/solutions/microsoft-365-limit-sharing?view=o365-worldwide "Limit Sharing in Microsoft 365") 

Once organisations control access this way there is a need to establish an operational procedure for employees to request that a guest is added to the tenant. The **Request-a-guest** app supports this requirement by providing a method for employees to request that a guest is added to the tenant and allows only authorised users to approve these requests.

- Provides a simple form for employees to request a guest is added to the tenant.
- In built approval process to only progress requests if the guest domain is on the allow list (if required).
- Provides fully audited workflow to inform helpdesk or SecOps when a request is submitted, rejected or approved.
- Once approved, guest invites are automatically issued.
- When the invite is issued the original requestor is added as the manager of the guest. This helps to ensure that the guest can be tracked back to the original requestor

![New Request](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/request-a-guest_form.png "New Request")
*New Request form*

**Request Process Wizard:**

- Either from a Microsoft teams tab or directly from PowerApps, end users will complete a form to request that a guest is added into the tenant. End users need to provide guest details and a justification.

- Once the request is submitted the guest domain is verified as approved. This is done by checking that the domain is in compliance with the settings in your AAD allow/block list for guest users.

- Members of an approvers group will then see the request in the 'Approve requests' tab of the Request-a-guest app and can choose to approve or reject the request.

- An adaptive card is also sent to a designated Team and Channel to allow reviewers to approve or deny requests directly from the adaptive card.

- Approvals can be submitted either via the app or using the Teams adaptive card.

- Requests and approval notifications are sent to the approval mailbox for auditing and history tracking if required.

- The user who requested the guest is informed both through the app and via a Teams chat message.

![My Requests](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/request-a-guest_myRequests.png "My Requests")  
*My Requests page*
<br/>
<br/>

![Approve Requests](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/request-a-guest_ApproveRequests1.png "Approve Requests")  
*Approve requests within the app*
<br/>
<br/>

![Approve Requests](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/request-a-guest_ApproveRequests2.png "Approve Requests")  
*Provide a comment on approval or rejection*
<br/>
<br/>

![Teams Approval](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/rag-teams-approval.png "Approve Requests")

*Approve or decline requests with a Teams adaptive card*
<br/>
<br/>

![My Approve Requests](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/request-a-guest_myRequestsApproved.png "My Approve Requests")  
*End user notification of approval or rejection in the app*
<br/>
<br/>

![Teams Approval Notification](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Images/rag-guest-approved-teams.png "Teams Approval Notification")  
*Teams chat message back to the end user with the verdict*
<br/>
<br/>

## Legal notice

This app template is provided under the [MIT License](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/blob/master/LICENSE) terms.  In addition to these terms, by using this app template you agree to the following:

- You, not Microsoft, will license the use of your app to users or organization. 

- This app template is not intended to substitute your own regulatory due diligence or make you or your app compliant with respect to any applicable regulations, including but not limited to privacy, healthcare, employment, or financial regulations.

- You are responsible for complying with all applicable privacy and security regulations including those related to use, collection and handling of any personal data by your app. This includes complying with all internal privacy and security policies of your organization if your app is developed to be sideloaded internally within your organization. Where applicable, you may be responsible for data related incidents or data subject requests for data collected through your app.

- If the app template enables access to any Microsoft Internet-based services (e.g., Office365), use of those services will be subject to the separately-provided terms of use. In such cases, Microsoft may collect telemetry data related to app template usage and operation. Use and handling of telemetry data will be performed in accordance with such terms of use.

- Use of this template does not guarantee acceptance of your app to the Teams app store. To make this app available in the Teams app store, you will have to comply with the [submission and validation process](https://docs.microsoft.com/en-us/microsoftteams/platform/concepts/deploy-and-publish/appsource/publish), and all associated requirements such as including your own privacy statement and terms of use for your app.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

## Getting started

Begin with the [Architecture](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Architecture) to read about what the app does and how it works.

When you're ready to try out Request-a-guest app, or to use it in your own organization, follow the steps in the [Deployment guide](https://github.com/OfficeDev/microsoft-teams-apps-request-a-guest/wiki/Deployment-Guide).

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
