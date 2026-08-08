# STC12 model test results

## Test images

All compiled with SDCC 4.2.0 or the hosted compiler at stc-compiler.vercel.app.

### 01-blink (from stc/src/01-blink)
- board_init: P1M0=0x03 (push-pull on P1.0/P1.1)
- delay_init: AUXR.7=0 (12T), TMOD=0x01 (mode 1)
- Timer starts, P1.0 toggles (LED pattern confirmed)

### 02-adc (from stc/src/02-adc)
- ADC_CONTR: power-on, start, flag set after conversion delay
- P1ASF: 0x08 (P1.3 as analog), P1M1: 0x08 (input-only)
- ADC_RES: 0x80 (mid-scale synthetic), ADC_RESL: 0x00
- NOTE: synthetic values only, not validated on silicon

### scheduler_test (cooperative scheduler pattern)
- Timer 0 ISR at FOSC/12, mode 1, reload 0xFC66
- IE=0x82 (EA+ET0), TR0=1, TF0 cleared by ISR
- bw_ms counter increments correctly (2 after ~15000 osc clocks)
- Proves: interrupt vector, ISR entry/exit, volatile access all work

## Timer verification

| Mode | Input | Expected | Actual |
|------|-------|----------|--------|
| 12T (AUXR.7=0) | 12 osc ticks | 1 timer count | 1 |
| 1T (AUXR.7=1) | 12 osc ticks | 12 timer counts | 12 |
| 12T overflow | reload 0xFC66, 11064 ticks | TF0 set | TF0 set |

## PCA verification

| Source | Input | Expected | Actual |
|--------|-------|----------|--------|
| FOSC/12 | 12 osc ticks | 1 PCA count | 1 |
| FOSC/2 | 10 osc ticks | 5 PCA counts | 5 |

## Differential execution (C52 vs STC12)

SFR map differs exactly as expected:
- C52 has T2CON at 0xC8; STC12 has P5
- STC12 has all extended SFRs (AUXR, PxM0/PxM1, ADC_*, PCA, etc.)
- Register values match at equivalent program points
