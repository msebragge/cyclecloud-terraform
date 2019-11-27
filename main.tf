locals {
  virtual_machine_name = "${var.prefix}-vm"
}

provider "azurerm" {
  # Whilst version is optional, we /strongly recommend/ using it to pin the version of the Provider being used
  version = "=1.36.0"
}


resource "azurerm_virtual_machine" "cc_tf_vm" {
  name                  = "${local.virtual_machine_name}"
  resource_group_name   = "${azurerm_resource_group.cc_tf_rg.name}"
  location              = "${azurerm_resource_group.cc_tf_rg.location}"
  network_interface_ids = ["${azurerm_network_interface.cc_tf_nic.id}"]
  vm_size               = "${var.machine_type}"

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  identity {
    type = "SystemAssigned"
  }

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.6"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${local.virtual_machine_name}-osdisk"
    disk_size_gb      = "128"
    caching           = "ReadWrite"
    create_option     = "Empty"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.cyclecloud_computer_name}"
    admin_username = "${var.cyclecloud_username}"
    admin_password = "${var.cyclecloud_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

data "azurerm_builtin_role_definition" "contributor" {
  name = "Contributor"
}


resource "azurerm_role_assignment" "cc_tf_mi_role" {
  name               = "${azurerm_virtual_machine.cc_tf_vm.name}"
  scope              = "${data.azurerm_subscription.primary.id}"
  role_definition_id = "${data.azurerm_subscription.subscription.id}${data.azurerm_builtin_role_definition.contributor.id}"
  principal_id       = "${lookup(azurerm_virtual_machine.cc_tf_vm.identity[0], "principal_id")}"
}


resource "azurerm_virtual_machine_extension" "fetch_cyclecloud_install_script" {
  name                 = "CustomScriptExtension"
  location             = "${azurerm_resource_group.cc_tf_rg.location}"
  resource_group_name  = "${azurerm_resource_group.cc_tf_rg.name}"
  virtual_machine_name = "${azurerm_virtual_machine.cc_tf_vm.name}"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.4"
  depends_on           = ["${azurerm_virtual_machine.cc_tf_vm}"]

  settings = <<SETTINGS
    {
        "commandToExecute": "curl -k -L -o /tmp/install_cyclecloud.py \
            'https://raw.githubusercontent.com/bwatrous/cyclecloud-terraform/master/scripts/cyclecloud_install.py'"
    }
SETTINGS
}


resource "azurerm_virtual_machine_extension" "install_cyclecloud" {
  name                 = "CustomScriptExtension"
  location             = "${azurerm_resource_group.cc_tf_rg.location}"
  resource_group_name  = "${azurerm_resource_group.cc_tf_rg.name}"
  virtual_machine_name = "${azurerm_virtual_machine.cc_tf_vm.name}"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.4"
  depends_on = ["${azurerm_virtual_machine_extension.fetch_cyclecloud_install_script}"]

#   settings = <<SETTINGS
#     {
#         "commandToExecute": "python /tmp/install_cyclecloud.py --acceptTerms --tenantId=${var.cyclecloud_tenant_id} \
#             --applicationId=${var.cyclecloud_application_id} --applicationSecret=${var.cyclecloud_application_secret} \
#             --username=${var.cyclecloud_username} --password=${var.cyclecloud_password} \
#             --storageAccount=${var.cyclecloud_storage_account} --hostname=${var.cyclecloud_dns_label}"
#     }
# SETTINGS
    
  settings = <<SETTINGS
    {
        "commandToExecute": "python /tmp/install_cyclecloud.py --acceptTerms --useManagedIdentity \
            --username=${var.cyclecloud_username} --password=${var.cyclecloud_password} \
            --storageAccount=${var.cyclecloud_storage_account} --hostname=${var.cyclecloud_dns_label}"
    }
SETTINGS
}