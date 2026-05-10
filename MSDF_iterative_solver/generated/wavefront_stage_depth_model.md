# Wavefront Stage-Depth Model

This report sizes the number of cascaded online PageRank iteration stages.
It is a sizing model, not an RTL result.

## Model

Full-wait baseline:

$$
T_{\mathrm{full}}(K)=K(D+\delta+B)
$$

Digit-stream wavefront:

$$
T_{\mathrm{wave}}(K)=D+K\delta+(K-1)F
$$

where:

- $D=14$ is the committed state digit width.
- $\delta=10$ is the usable online output delay.
- $B=4$ is the full-wait iteration barrier overhead.
- $F=1$ is any extra register/FIFO delay between stages.

## Sweep

| K stages | full-wait cycles | wavefront cycles | speedup | marginal speedup vs K-1 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 28 | 24 | 1.167x | 1.167x |
| 2 | 56 | 35 | 1.600x | 1.371x |
| 3 | 84 | 46 | 1.826x | 1.141x |
| 4 | 112 | 57 | 1.965x | 1.076x |
| 5 | 140 | 68 | 2.059x | 1.048x |
| 6 | 168 | 79 | 2.127x | 1.033x |
| 7 | 196 | 90 | 2.178x | 1.024x |
| 8 | 224 | 101 | 2.218x | 1.018x |
| 9 | 252 | 112 | 2.250x | 1.015x |
| 10 | 280 | 123 | 2.276x | 1.012x |
| 11 | 308 | 134 | 2.299x | 1.010x |
| 12 | 336 | 145 | 2.317x | 1.008x |
| 13 | 364 | 156 | 2.333x | 1.007x |
| 14 | 392 | 167 | 2.347x | 1.006x |
| 15 | 420 | 178 | 2.360x | 1.005x |
| 16 | 448 | 189 | 2.370x | 1.005x |

## Recommendation

Recommended first RTL depth: **K=4**.

Reasoning:

- K must not exceed the number of PageRank iterations we want to fuse.
- Area grows approximately linearly with K because each stage needs its own row engines/residual state.
- K beyond the recommendation has diminishing total-speedup gain under the current delay model.
- K=4 is the minimum useful paper checkpoint because it demonstrates more than a two-stage handoff.
- K=8 is the practical upper checkpoint for the next sweep; deeper K should wait for routed resource data.

## JSON

```json
{
  "params": {
    "data_width": 14,
    "online_delay": 10,
    "boundary": 4,
    "inter_stage_delay": 1,
    "max_stages": 16,
    "max_practical_stages": 8,
    "min_marginal_speedup": 1.05
  },
  "recommended": 4,
  "rows": [
    {
      "k": 1,
      "full_wait": 28,
      "wavefront": 24,
      "speedup": 1.1666666666666667,
      "marginal": 1.1666666666666667
    },
    {
      "k": 2,
      "full_wait": 56,
      "wavefront": 35,
      "speedup": 1.6,
      "marginal": 1.3714285714285714
    },
    {
      "k": 3,
      "full_wait": 84,
      "wavefront": 46,
      "speedup": 1.826086956521739,
      "marginal": 1.141304347826087
    },
    {
      "k": 4,
      "full_wait": 112,
      "wavefront": 57,
      "speedup": 1.9649122807017543,
      "marginal": 1.0760233918128654
    },
    {
      "k": 5,
      "full_wait": 140,
      "wavefront": 68,
      "speedup": 2.0588235294117645,
      "marginal": 1.0477941176470589
    },
    {
      "k": 6,
      "full_wait": 168,
      "wavefront": 79,
      "speedup": 2.1265822784810124,
      "marginal": 1.0329113924050632
    },
    {
      "k": 7,
      "full_wait": 196,
      "wavefront": 90,
      "speedup": 2.1777777777777776,
      "marginal": 1.0240740740740741
    },
    {
      "k": 8,
      "full_wait": 224,
      "wavefront": 101,
      "speedup": 2.217821782178218,
      "marginal": 1.0183875530410185
    },
    {
      "k": 9,
      "full_wait": 252,
      "wavefront": 112,
      "speedup": 2.25,
      "marginal": 1.0145089285714284
    },
    {
      "k": 10,
      "full_wait": 280,
      "wavefront": 123,
      "speedup": 2.2764227642276422,
      "marginal": 1.011743450767841
    },
    {
      "k": 11,
      "full_wait": 308,
      "wavefront": 134,
      "speedup": 2.298507462686567,
      "marginal": 1.0097014925373133
    },
    {
      "k": 12,
      "full_wait": 336,
      "wavefront": 145,
      "speedup": 2.317241379310345,
      "marginal": 1.008150470219436
    },
    {
      "k": 13,
      "full_wait": 364,
      "wavefront": 156,
      "speedup": 2.3333333333333335,
      "marginal": 1.0069444444444444
    },
    {
      "k": 14,
      "full_wait": 392,
      "wavefront": 167,
      "speedup": 2.3473053892215567,
      "marginal": 1.0059880239520957
    },
    {
      "k": 15,
      "full_wait": 420,
      "wavefront": 178,
      "speedup": 2.359550561797753,
      "marginal": 1.0052166934189406
    },
    {
      "k": 16,
      "full_wait": 448,
      "wavefront": 189,
      "speedup": 2.3703703703703702,
      "marginal": 1.0045855379188713
    }
  ]
}
```
