## Request-a-Guest - Domain Check Script
<#
---------------------------------------------------------------------------------------------------------------------------
Authors : Tobias Heim (Sr. Customer Engineer - Microsoft)
          Kris Wilson (Sr. Customer Engineer - Microsoft)
Version : 1.0
-----------------------------------------------------------------------------------------------------------------------------------
DISCLAIMER:
   THIS CODE IS SAMPLE CODE. THESE SAMPLES ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.
   MICROSOFT FURTHER DISCLAIMS ALL IMPLIED WARRANTIES INCLUDING WITHOUT LIMITATION ANY IMPLIED WARRANTIES
   OF MERCHANTABILITY OR OF FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK ARISING OUT OF THE USE OR
   PERFORMANCE OF THE SAMPLES REMAINS WITH YOU. IN NO EVENT SHALL MICROSOFT OR ITS SUPPLIERS BE LIABLE FOR
   ANY DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS PROFITS, BUSINESS
   INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR OTHER PECUNIARY LOSS) ARISING OUT OF THE USE OF OR
   INABILITY TO USE THE SAMPLES, EVEN IF MICROSOFT HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
   BECAUSE SOME STATES DO NOT ALLOW THE EXCLUSION OR LIMITATION OF LIABILITY FOR CONSEQUENTIAL OR
   INCIDENTAL DAMAGES, THE ABOVE LIMITATION MAY NOT APPLY TO YOU.
#>
Param (
    [Parameter (Mandatory = $true)][string]$queryDomain
)

# Import Module
Import-Module AzureADPreview
# Connect to Azure AD
Connect-AzureAD -Credential (Get-AutomationPSCredential -Name 'ragGuest') |Out-Null

# Get Azure AD Policy
$B2BPolicy = Get-AzureADPolicy -All:$true | Where-Object {$_.DisplayName -eq "B2BManagementPolicy"}
# Check if Policy exisits
if ($B2BPolicy) {
   
    # Get all allowed domains
    $AllowedDomains = ($B2BPolicy.definition |convertfrom-json).B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.AllowedDomains
    # Get all blocked domains
    $BlockedDomains = ($B2BPolicy.definition |convertfrom-json).B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.BlockedDomains
    
    # Check if allowed domains are configured
    if ($AllowedDomains) {
        # Compare requested against allowed domains
        if ($AllowedDomains | Where-Object {$_ -eq ("*." + $queryDomain) -or $_ -eq $queryDomain -or $_ -eq (($queryDomain.Split('.'))[-0] + ".*")}) {
            $Result = $true
        } else {$Result = $false}
    # Check if insteed of allowed blocked domains are configured
    } else {
        # Compare requested against blocked domains
        if ($BlockedDomains | Where-Object {$_ -eq ("*." + $queryDomain) -or $_ -eq $queryDomain -or $_ -eq (($queryDomain.Split('.'))[-0] + ".*")}) {
            $Result = $false
        } else {$Result = $true}
    }
}
else {
    # Domain Restriction Policy is not yet configured - All domains are allowed
    $Result = $true
}
# Create result object
$objOut = [PSCustomObject]@{
    DomainCheckResult = $Result  
}
# Respond with result
Write-Output ( $objOut | ConvertTo-Json)