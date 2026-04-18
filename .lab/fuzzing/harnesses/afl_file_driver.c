#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv)
{
    FILE *f;
    long sz;
    uint8_t *buf;
    size_t n;

    if(argc < 2){
        return 0;
    }

    f = fopen(argv[1], " rb)
