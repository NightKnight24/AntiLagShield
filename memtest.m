#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_host.h>

int main() {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    vm_statistics_data_t vm_stat;
    host_page_size(host_port, &pagesize);
    if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) == KERN_SUCCESS) {
        unsigned long long free_bytes = (unsigned long long)(vm_stat.free_count + vm_stat.speculative_count) * pagesize;
        unsigned long long inactive_bytes = (unsigned long long)vm_stat.inactive_count * pagesize;
        printf("Free+Speculative: %llu MB, Inactive: %llu MB\n", free_bytes / (1024*1024), inactive_bytes / (1024*1024));
    }
    return 0;
}
