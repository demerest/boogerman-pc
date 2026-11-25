/* Boogerman M3 path (a): reference-Z80 cosim harness.
 * Runs the UPLOADED driver image (boot-z80_ram.bin) in superzazu with a faithful
 * bus stub and CORRECT 68K stimuli, to determine whether the driver reaches the
 * DAC-start/ack when given proper triggers (isolates superzazu vs native sched).
 * Build: cl /I ..\segagenesisrecomp\runner\external\superzazu z80_ref_test.c ..\segagenesisrecomp\runner\external\superzazu\z80.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "z80.h"

static unsigned char ram[0x2000];
static unsigned char *rom; static long romlen;
static unsigned bank;
static unsigned long cyc;
static int log_writes = 1;

static void note(const char *tag, unsigned a, unsigned v) {
    if (log_writes) printf("[W] %s $%04X = $%02X (pc=$%04X)\n", tag, a, v, 0);
}

static uint8_t rb(void *u, uint16_t a) {
    (void)u;
    if (a < 0x2000) return ram[a & 0x1FFF];
    if (a >= 0x8000) { unsigned off = (bank << 15) | (a & 0x7FFF);
                       return off < (unsigned)romlen ? rom[off] : 0xFF; }
    if (a >= 0x4000 && a < 0x6000) return 0x00; /* YM status: busy clear */
    return 0xFF;
}
static void wb(void *u, uint16_t a, uint8_t v) {
    (void)u;
    if (a < 0x2000) { unsigned o = a & 0x1FFF;
        if (o==0x0FAC||o==0x0FE4||o==0x0FC2||o==0x0FAD) printf("[ZW] $%04X=$%02X pc=$%04X\n", o, v, ((z80*)u)->pc);
        ram[o] = v; return; }
    if (a == 0x6000) { bank = (bank & 0xFE) | (v & 1); return; }
    if (a >= 0x4000 && a < 0x6000) return; /* YM */
    if (a >= 0x7F00) return; /* PSG */
}
static uint8_t pin(z80 *z, uint8_t p) { (void)z;(void)p; return 0xFF; }
static void pout(z80 *z, uint8_t p, uint8_t v) { (void)z;(void)p;(void)v; }

int main(int argc, char **argv) {
    const char *ramp = argc>1?argv[1]:"..\\captures-us\\boot-z80_ram.bin";
    const char *romp = argc>2?argv[2]:"..\\..\\Boogerman (U) [!].gen";
    FILE *f = fopen(ramp, "rb"); if (!f) { printf("no ram\n"); return 1; }
    fread(ram, 1, 0x2000, f); fclose(f);
    f = fopen(romp, "rb"); if (!f) { printf("no rom\n"); return 1; }
    fseek(f, 0, SEEK_END); romlen = ftell(f); fseek(f, 0, SEEK_SET);
    rom = malloc(romlen); fread(rom, 1, romlen, f); fclose(f);

    static z80 z; z80_init(&z);
    z.read_byte = rb; z.write_byte = wb; z.port_in = pin; z.port_out = pout; z.userdata = &z;
    z.sp = 0x1FFF; z.pc = 0x0000;

    /* 68K stimuli: deposit cmd01; once consumed, issue DAC request + vblank flag. */
    ram[0x0FAC] = 0x01;
    int consumed = 0, triggered = 0;
    unsigned long total = 0;
    int hit16E0=0, hit1788=0, hit10B4=0;
    for (long i = 0; i < 4000000; i++) {
        uint16_t pc = z.pc;
        if (pc==0x16E0) hit16E0++;
        if (pc==0x1788) hit1788++;
        if (pc==0x10B4) hit10B4++;
        z80_step(&z); total += z.cyc; z.cyc = 0;
        if (!consumed && ram[0x0FAC]==0) { consumed = 1; printf("[68K] cmd01 consumed at step %ld\n", i); }
        if (consumed && !triggered && i > 0) {
            /* real 68K would start DAC / flag vblank after init ack */
            ram[0x0FC2] = 0x01; ram[0x0FAD] = 0xFE; triggered = 1;
            printf("[68K] set $0FC2=1 $0FAD=$FE at step %ld\n", i);
        }
        if (hit1788) { printf("[REF] ack $1788 reached at step %ld\n", i); break; }
    }
    printf("[REF] steps=%lu hit16E0=%d hit10B4=%d hit1788=%d $0FE4=$%02X\n",
            total, hit16E0, hit10B4, hit1788, ram[0x0FE4]);
    return 0;
}
