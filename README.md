# Pathtracing using the WebGL API

This is a **not** functional raytracer.
It is entirely written in Javascript, using the **WebGL2** API to carry out all computations.
Is kinda modular, allowing the end user to toggle some basic functionalities like "**un/biased** rendering", "**procedural sky**",
"next event estimation" and "**Bi-Directional** path tracing".

On low end devices the **GLSL** compiler usually is chocking with the amount of code
that is passed by the main **fragment** shader making it impossible to run.
Of course the amount of computational power needed to run the renderer depends on the complexity of the scene.
On my current system I have a GTX 960m and the driver doesn't crash that regularly, so anything with a floating point of performance of 1.5 GFLOPS and above should be running fine.

It seems to be working fine on Windows using Angle, Google Chrome is highly suggested as it gives me the lowest render times among
of all browsers.

### List of features
* generative texture mapping
* procedurally generated textures
* supports **color**, **emission** and **specular** textures
* supports raytracing of **Quadric** & **Euclidean** surfaces
* supports **raymarching** of signed distance fields
* **multiple** light sampling
* **Reinhard** tone mapping
* cosine weighted **importance sampling**

[**Demo**](https://mourtz.github.io/raytracer-0/)

---

### @ToDo List
* bump mapping
* split the main shader into three (**1st** for eye path tracing, **2nd** for light path tracing, **3rd** for merging the paths) to reduce the probability of crashing the driver during compilation.
* HLBVH support(some work has be done already)
* participating media
* volumetric SDF
* functional camera controls
* BSSRDF

## Future Plans
I have already started working on my next raytracer written in C++. The library I chose to use for GPU acceleration is **OpenCL** 1.2 by Khronos.
However, **Arrayfire** seems like a good tool I could make use of in the future.

## Gallery
![alt text](https://lh3.googleusercontent.com/jTXK1CFNzp9Fg8qose2BI3qdcA1xQX1YAPDUekB7av0U4dfk777A1yy78dO1ibnvU-S4VSY0d2dOxuu6-O4g3KFd_nBECdUTmnXWKUv3Km2nxodMkS827Guhd9A_H4eOcxdzrtIS8T8I8C5xuYq20k_eUnZNNCuE6nCOLV5Ljsd9E28EFVTufcXEv4yByu4XNErTgAp_CYJIcr-_qDtNyRWwmkWSGn23iZ3h1R7wGRrXMu9aTv8vN4JEdQOfMpbgh7OKFE_I0QyU9QkEJEgwfBnbzpy3dg-7izfLb2M0oWVxAXQzIXrvIbTlc-657EPFC8MuWiA_skTwZHtfdC2n7-fXlGrPrdJqR-e1_Fsgfgm6wetNp90dmGepklehN66WH8ljT1Gxw5tKNNhhHRAH74zTJoJLOh13l3_Xo06ocE5ngBO4SUOX7e2U5mVloHk_M7F6z9DMJ_EJ3EIcYmYmNcaFnALkxoEhW9KwuULn0SGq_df3CKTn5dlfzy2ozH6u73l1tY3xfkIs-0rZIsOZ3fL1WIflwPtwyn0MP_Tc5SPknnJ1bfc6pU8n5moUmZ838NAMsNKFJsmhwOC9UsD83J5c1wJH2J4xaR6XASdo_WZZ1uDBgU4hE_Ka1GDPGc5DTBSkJO6C-8PY0UC76RNGX9dCQBPkBA8yezI=s936-no)

![alt text](https://lh3.googleusercontent.com/g3vbb8KmefWG8mxd1orXT0TauAkQAQenXuIHnN1sKt29lmzuT_FLnKdtmmtU-1w8brZqn0yXvRfE_b-vrLBXKmq9oVTJ9s1PEkrhwOOnLnL7bo7rLd1AJgpow1zoy3reEUAURux5eJO1dqQgSwBAiYXxnv-_03L1KGZsHw3fTUCc3rOKhFo8dvVa6uRMTmokfNIiIRLFpDK8QKuygLOka4i_au2_HEfLZmWtPtIaOPJMzWT9_jWhJ_lEz0HzF1HwZZR-8PkpGgNfPlvdM5syaFxEsCnHWg4dwep6yoUqHHSZaBb4MhCDx_LjNbPV89JQhhgkkDGqCewY2thD5sk2P0LfDgMv4lbR-S5iKi3YR0RxFh2iOS0TCNMW6BYFHr65jUf2TYxMBzHPL8yVIGUGqIx79tSb4p6bBpjQ2ZEgwxJi2P3u4k1yDsAJzk2HY81NuhE-kthjzeG5T4V6FcQGC7M6QWeZBUHtA0-4Cm-6KvHSJ9K7MnNU0VoIYrFilFTtt9ljKPqWIZhYdL-f1gZERb6oNV_Lv-OIm93PBHf0YCryumA_XzJIWbE1jqNky9L5S3QgPyO7RL0viT8lSmZufgsIZKqC0R_wkux5rqzFwjNA6_Cs7ZHt23xKI1PxhmWOm9Pm7oWXy2bAq26DddWxcHLKfoCrZV91oJc=s936-no)

![alt text](https://lh3.googleusercontent.com/j82WJfHnX_PdGW_bkmX77cV2FRjgH9Egr4WC6Fnt8_z_UA8Os92NNOWmc1dXoWcKahJ4TPilBaLF0okbMzES2tMqA9oLV9NleOeUPNmLrGhJe7cBnQGeDHD5tUY6ypc-4JWaqCAvYQvqohnW8h7jqQ0Z3Tgs0vd305GI_B7LOsYgXpHjncEATer3AwlI4jGlshvmXh99bCAJnpjDOo3V0XQ9O8k5acUGYB6jxpj6Ag_8bnqB7px037LZFPsLHQWOIuYgusHLlTh_GsztoWo8xczKq42ayjYEq98jk0wNauFmyZiSozI6Ut8umGJxm--_8tJpFYMvBbjHmcMCCZJgiM--6tAueOyyqcjBoWAF3YarfpxyD9Nd9kqrpy-IJcSCkhsHJns8bJFd8O97xHVuKmtp8S-okfd9JJF5uyd6DkKkIVCC5fjrvc1bWNn1Z6_T2wIDA3MJyvuCRG9Ko2h-5S1IPzM5vy4Uss0JMuZJT_UC_0E461xynUTimRMjXh2JJlx_Vm3xeS41x0rTBvIj5L52rRYSJWQgeCLdMblb37CGFVj3YDMXvPIX4FQTqrRqzDQxevMHFU6tKtCxcWMhLSXX2ekaYq3vwbd8PJDmyr3eX4R4ZUcp0L1FyijpbDeSOafUknXYVHqp51o5Il76xa1nGSInGj9psE8=s936-no)

[Show more](https://goo.gl/photos/4zafwXUs4Ph9rux48)

## Credits
[iq](http://www.iquilezles.org/) - Inigo quilez <br>
[Toshiya Hachisuka](http://www.ci.i.u-tokyo.ac.jp/~hachisuka/) - Toshiya Hachisuka <br>
[reinder](http://reindernijhoff.net/) - Reinder Nijhoff <br>
[erichlof](https://github.com/erichlof) - Erich Loftis <br>
