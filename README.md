# actions-setup-msvc-env
GitHub Action: setup MSVC environment variables

## Useage

### Inputs

```yaml
- uses: h20y6m/actions-setup-msvc-env@v1
  with:
    # Target architecture.
    # Optional. Default is $RUNNER_ARCH.
    arch:

    # Windows SDK version.
    # Optional. Default is latest installed version.
    sdk:

    # VC++ compiler toolset version.
    # Optional. Default is latest installed version.
    toolset:

    # Visual Studio version.
    # Optional. Default is latest installed version.
    vsversion:
```
