# ==============================================================================
# КОНФІГУРАЦІЯ
# ==============================================================================

# !!! КРИТИЧНЕ ВИПРАВЛЕННЯ 1: ЗМІНА ЛОКАЦІЇ НА CANADACENTRAL (Канада) !!!
# Це вирішує проблему недоступності VM SKU у uksouth.
$location = "canadacentral" 
$resourceGroupName = "mate-azure-task-12"
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"

# Зчитуємо відкритий SSH-ключ. Припускаємо, що він знаходиться у стандартному місці.
$sshKeyPublicKey = Get-Content "~/.ssh/id_rsa.pub"
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"

# Розмір VM залишаємо Standard_D2s_v3. Сподіваємося, що він доступний у canadacentral.
$vmSize = "Standard_D2s_v3"
$dnsLabel = "matetask" + (Get-Random -Count 1)

# !!! КРИТИЧНО ВАЖЛИВО: ЗАМІНИТИ СЮДИ ВАШ GITHUB USERNAME !!!
$githubUsername = "Langrafka"

# ==============================================================================
# СТВОРЕННЯ РЕСУРСІВ AZURE
# ==============================================================================

Write-Host "Creating a resource group $resourceGroupName in $location..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

Write-Host "Creating a network security group $networkSecurityGroupName ..."
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH  -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow;
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow;
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP

Write-Host "Creating Virtual Network $virtualNetworkName and Subnet $subnetName ..."
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet

Write-Host "Creating SSH Key $sshKeyName ..."
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey

Write-Host "Creating Public IP Address $publicIpAddressName with DNS label $dnsLabel ..."
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Standard -AllocationMethod Static -DomainNameLabel $dnsLabel

Write-Host "Creating Virtual Machine $vmName ..."
# Зверніть увагу, що тут з'явиться запитання про облікові дані (User), його потрібно буде ввести вручну
New-AzVm `
-ResourceGroupName $resourceGroupName `
-Name $vmName `
-Location $location `
-image $vmImage `
-size $vmSize `
-SubnetName $subnetName `
-VirtualNetworkName $virtualNetworkName `
-SecurityGroupName $networkSecurityGroupName `
-SshKeyName $sshKeyName  -PublicIpAddressName $publicIpAddressName

# ==============================================================================
# РОЗГОРТАННЯ CUSTOM SCRIPT EXTENSION
# ==============================================================================

Write-Host "Deploying Custom Script Extension to install web app..."

# URI до скрипту встановлення (використовуємо ваш форк)
$fileUri = "https://raw.githubusercontent.com/$githubUsername/azure_task_12_deploy_app_with_vm_extention/main/install-app.sh"

$Params = @{
    ResourceGroupName  = $resourceGroupName
    VMName             = $vmName
    Name               = 'CustomScriptAppInstall' # Унікальне ім'я розширення
    Publisher          = 'Microsoft.Azure.Extensions'
    ExtensionType      = 'CustomScript'
    TypeHandlerVersion = '2.1'
    # Використовуємо ProtectedSettings, щоб URL не був видно у властивостях VM
    ProtectedSettings  = @{
        fileUris = @($fileUri)
        commandToExecute = './install-app.sh'
    }
}

# !!! КРИТИЧНЕ ВИПРАВЛЕННЯ 2: Виправлено синтаксис ForceRerun !!!
# Використовуємо $((Get-Date).Ticks.ToString()) для створення унікального рядка.
Set-AzVMExtension @Params -Force -ForceRerun $((Get-Date).Ticks.ToString())

Write-Host "Custom Script Extension deployment initiated. Check http://$dnsLabel.$location.cloudapp.azure.com:8080 once deployment completes."