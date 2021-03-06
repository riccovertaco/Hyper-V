# VMQ Autoconfiguration script
# Enables VMQ on selected NICs, and assigns processors to NICs for VMQing based on the number of available processors
# This runs on the assumption that you want to assign the maximum amount of processors to each network adapter so that each adapter has the same number of processors, with no overlap
# V0.2 - 6/4/2015
# Vincent Bushong

# Processor information gathering
write-host "Getting number of instances of Win32_Processor..."
[array]$processorArray = (get-wmiobject -class win32_processor)
$processorInstances = $processorArray.count

# Get number of processors for one instance of Win32_Processor, multiply by number of instances
write-host "Calculating logical processors..."
$logicalProcessorsPart = (get-wmiobject -class win32_processor | select DeviceID, numberOfLogicalProcessors | where-object { $_.DeviceID -eq "CPU0" }).NumberOfLogicalProcessors
$logicalProcessors = $logicalProcessorsPart * $processorInstances
write-host "Number of logical processors: $logicalProcessors"

# Same thing as with the processors; get cores per instance, multiply by instances
write-host "Calculating cores..."
$coresPart = (get-wmiobject -class win32_processor | Select DeviceID,NumberofCores | where-object { $_.DeviceID -eq "CPU0" }).NumberOfCores
$cores = $coresPart * $processorInstances
write-host "Number of cores: $cores"

# Determine if hyper-threading is enabled.
$hyperthreading
if ($logicalProcessors -eq $cores){
    $hyperthreading = $false
    write-host "Hyper-threading appears to be disabled."
} elseif ($logicalProcessors/$cores -eq 2) {
    $hyperthreading = $true
    write-host "Hyper-threading appears to be enabled."
} else {
    # If this happens, it's probably due to incompetent scripting rather than an actual problem.
    write-host "Number of cores and logical processors cannot be reconciled. Aborting."
    Exit
}

# Gets raw NIC netconnectionid data
$rawNIC = get-wmiobject win32_networkadapter -filter "netconnectionstatus = 2" | select netconnectionid

# Assigns each netconnectionid from network adapters to an element in array $availableNICs
$availableNICs = New-Object System.Collections.ArrayList
foreach ($netconnectionid in $rawNIC){
    $availableNICs.Add(($netconnectionid).netconnectionid) > $null
}

$NICs = New-Object System.Collections.ArrayList
[int]$menuChoice = -1
while ( $menuChoice -ne 0 ){
  Write-host "Please select the NICs you wish to use with your VMQ:"
  foreach($NIC in $availableNICs){
    $menuNumber = ($availableNICs.IndexOf($NIC) + 1)
    write-host "$menuNumber - $NIC"
  }
    [Int]$menuChoice = read-host "Choose a number and press enter; 0 when finished"
    $indexChoice = $menuChoice - 1
    if ($indexChoice -lt $availableNICs.count -and $indexChoice -ge 0){
        $NICs.add($availableNICs[$indexChoice]) > $null
        $availableNICs.removeat($indexChoice)
    }
    
}

$numberOfNIC = $NICs.count

if ($numberOfNIC -eq 0){
    write-host "No NICs selected. Aborting."
    Exit
}

# Takes the number of logical processors, subtracts one (when using a VMQ, you must start with processor 2)
$availableProcessors = ($logicalProcessors - 1)
# Subtracts enough processors so that $available processors is divisible by the number of NICs
$availableProcessors -= ($availableProcessors % $numberOfNIC)

# The setup function, using set-netadaptervmq
function assignProcessors($processorsPerNIC){
    write-host "Configuring..."
    if ($hyperthreading -eq $false){
        for ($i = 0; $i -lt $numberOfNIC; $i++){
            $baseprocessornumber = 2 + $processorsPerNIC * $i
            $maxprocessornumber = $baseprocessornumber + ($processorsPerNIC - 1)
            set-netadaptervmq $NICs[$i] -enabled $true -baseprocessorgroup 0 -baseprocessornumber $baseprocessornumber -maxprocessornumber $maxprocessornumber -maxprocessors $processorsPerNIC
        }
    } else {
        for ($i = 0; $i -lt $numberOfNIC; $i++){
            $baseprocessornumber = 2 + $processorsPerNIC * $i
            $maxprocessornumber = $baseprocessornumber + ($processorsPerNIC - 1)
            $baseprocessornumber += $baseprocessornumber - 2
            $maxprocessornumber += $maxprocessornumber - 2
            set-netadaptervmq $NICs[$i] -enabled $true -baseprocessorgroup 0 -baseprocessornumber $baseprocessornumber -maxprocessornumber $maxprocessornumber -maxprocessors $processorsPerNIC
        }
    }
}

if($availableProcessors/$numberOfNIC -lt 1){
    write-host "Processors cannot be evenly allocated across all chosen NICs. Autoconfig will exit without making changes."
    Exit
} elseif ($availableProcessors/$numberOfNIC -lt 2) {
    write-host "1 processor will be assigned to each NIC."
    assignProcessors(1)
} elseif ($availableProcessors/$numberOfNIC -lt 4) {
    write-host "2 processors will be assigned to each NIC."
    assignProcessors(2)
} elseif ($availableProcessors/$numberOfNIC -lt 8) {
    write-host "4 processors will be assigned to each NIC."
    assignProcessors(4)
} elseif ($availableProcessors/$numberOfNIC -ge 8) {
    write-host "8 processors will be assigned to each NIC."
    assignProcessors(8)
} else {
    write-host "An unknown error occured; autoconfig will exit without making changes."
    Exit
}

write-host ""
write-host "Please verify these settings are correct:"
foreach ($NIC in $NICs) {
get-netadaptervmq  $NIC | FL
}