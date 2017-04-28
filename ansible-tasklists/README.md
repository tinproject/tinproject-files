# Ansible tasklists

This folder holds a series of _Ansible tasklists_, or [_Task Include Files_](https://docs.ansible.com/ansible/playbooks_roles.html#task-include-files-and-encouraging-reuse), that are yaml files that contains a series of _tasks_ to perform a concrete goal.

Usually contains little work that don't justify the creation of a custom _role_ or use a _Ansible Galaxy role_ with full configuration options. 

These files encourage reuse, just drag & drop the file and use it.


It can be used in _playbooks_ or _roles_ using the `include` Ansible statement.
