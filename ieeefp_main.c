#include <stdio.h>
#include <stdint.h>

extern uint32_t ieeefp(uint32_t, float, float);

int main(int argc, char **argv)
{
    float a,b,f;
    uint32_t ai,bi,r;
    unsigned int i,op;
    char opch;

    if (argc!=4) {
        fprintf(stderr, "Usage: %s <operation> <float> <float>\n", argv[0]);
        fprintf(stderr, "operation: 0=add,1=subtract,2=multiply,3=divide\n");
        return 1;
    }

    sscanf(argv[1], "%d", &op);
    sscanf(argv[2], "%f", &a);
    sscanf(argv[3], "%f", &b);

    ai = *((uint32_t *) &a);
    bi = *((uint32_t *) &b);
    printf("%.8X, %.8X\n", ai, bi);

    r = ieeefp(op, a, b);
    if (op<4)
        opch = "+-*/"[op];
    else
        opch = '?';

    /* ieeefp() uses 32-bit representations,
       but the C calling convention for a float expects an
       80-bit floating-point register ST(0) to be returned
       - so just use casts instead.
    */
    f = *((float *) &r);
    printf("%f %c %f = %f (%.8X)\n", a, opch, b,f,r);

    return 0;
}
