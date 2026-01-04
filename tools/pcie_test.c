/*
 * PCIe BAR0 Memory Test Utility
 *
 * Usage: sudo ./pcie_test [device]
 * Example: sudo ./pcie_test 0000:02:00.0
 *
 * Compile: gcc -o pcie_test pcie_test.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <unistd.h>
#include <string.h>

#define BAR0_SIZE 4096

int main(int argc, char *argv[]) {
    const char *device = "0000:02:00.0";
    char path[256];

    if (argc > 1) {
        device = argv[1];
    }

    snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/resource0", device);

    int fd = open(path, O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open");
        fprintf(stderr, "Failed to open %s\n", path);
        fprintf(stderr, "Make sure:\n");
        fprintf(stderr, "  1. Device exists: lspci -s %s\n", device);
        fprintf(stderr, "  2. Memory enabled: sudo setpci -s %s COMMAND=0x06\n", device);
        fprintf(stderr, "  3. Running as root\n");
        return 1;
    }

    void *map = mmap(NULL, BAR0_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }

    volatile uint32_t *ptr = (volatile uint32_t *)map;

    printf("PCIe BAR0 Test - Device: %s\n", device);
    printf("==========================================\n\n");

    printf("Reading first 16 DWORDs:\n");
    for (int i = 0; i < 16; i++) {
        printf("  [0x%02X]: 0x%08X\n", i * 4, ptr[i]);
    }

    printf("\nWrite test:\n");
    uint32_t test_val = 0xDEADBEEF;
    printf("  Writing 0x%08X to offset 0x00...\n", test_val);
    ptr[0] = test_val;
    uint32_t readback = ptr[0];
    printf("  Readback: 0x%08X\n", readback);

    if (readback == test_val) {
        printf("\n  SUCCESS: Write/read verified!\n");
    } else if (readback == 0xFFFFFFFF) {
        printf("\n  FAILED: Device not responding (completion timeout)\n");
        printf("  Check: link status, user logic running, BAR enabled\n");
    } else {
        printf("\n  WARNING: Readback mismatch\n");
    }

    munmap(map, BAR0_SIZE);
    close(fd);
    return 0;
}
