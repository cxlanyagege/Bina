# Keep Awake performance baseline

This baseline compares two Release builds of the standalone Keep Awake tool before it joined Bina. The builds were sampled on Apple silicon with macOS 27.3 (26C5047e) and Xcode 27.2. The comparison build used an empty window, and both builds shared their app and extension bundle identifiers.

| Build | Window | Display mode | CPU in each sample | Physical memory | `IDLEW` change over 15 s |
| --- | --- | --- | ---: | ---: | ---: |
| Empty window | Open | Follow system settings | 0.0% | 32M | 0 |
| Empty window | Open | Keep display awake | 0.0% | 26M | 0 |
| Empty window | Closed | Keep display awake | — | — | — |
| Toolbox | Open | Follow system settings | 0.0% | 38M | 0 |
| Toolbox | Open | Keep display awake | 0.0% | 38M | 0 |
| Toolbox | Closed | Keep display awake | 0.0% | 37M | 0 |

Closing the empty window ended its process and released the assertion. The toolbox kept the same process and assertion after closing the window, and reopening showed the active state. Quitting released the assertion.

For future comparisons, build Release and identify the PID of the app being measured. Let the app settle after each transition, then take four `top` samples at five-second intervals and discard the first CPU reading.

```sh
top -c n -l 4 -s 5 -r -pid "$toolbox_pid" -stats pid,cpu,mem,idlew
pmset -g assertions
```

Use the memory values reported in `MEM` and subtract the initial `IDLEW` counter from the final one. Check `pmset` before and after the sampling interval so the recorded mode matches the assertion actually held by the app. The open window should stay visible and idle during its samples. For the closed-window case, close it while keeping the app running.

These are short process measurements of the standalone app. CPU percentages and memory sizes use `top`’s display precision. Display power and the work of system UI processes are outside the measurement.
