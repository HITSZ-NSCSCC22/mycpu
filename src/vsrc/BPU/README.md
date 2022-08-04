# Branch Predictor Unit

## Final MPKI

Using 

- 16K-Entry Base Predictor

- 2K-Entry Tagged Predictor

- 3-bits CTR, 3bits Useful, 13-bits Tag

each of the table is less then 36K, in order to fit in a BRAM of xc7a FPGA

```
MPKI: 1.65644
MPKI: 0.887665
MPKI: 0.0851187
MPKI: 0.105119
MPKI: 0.0329153
MPKI: 1.02339
MPKI: 5.97177
MPKI: 8.59235
MPKI: 1.10197
MPKI: 0.326644
MPKI: 7.55845
MPKI: 9.7676
MPKI: 0.43156
MPKI: 1.42641
MPKI: 4.27732
MPKI: 1.33129
MPKI: 1.33265
MPKI: 3.55453
MPKI: 2.52962
MPKI: 2.19501
Avg: 2.70
```

## MPKI with on-board config

With new entry opt:
Average MPKI: 2.64501

No new entry opt:
Average MPKI: 2.62932
