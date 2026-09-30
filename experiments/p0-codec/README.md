# P0-CODEC 디코더 실험

P0 기술 선택용 실험이다. 앱·GPU·측정·제품 지원 완료를 뜻하지 않는다. 기준 commit `ea7e2b3`, 실제 실행 환경과 독립 비교 결과는 `results/`에 기록한다.

## 실행

```sh
bash experiments/p0-codec/run.sh all
# 한 feature 조합만 실행
bash experiments/p0-codec/run.sh combined-c
```

uv가 필요하다. Python 3.12.13과 참조 패키지는 `requirements.txt`, Rust와 dicom-rs는 `rust/rust-toolchain.toml`·`Cargo.toml`·`Cargo.lock`으로 고정한다. 빌드·참조 배열·생성 DICOM은 기본 `~/Library/Caches/dicom-viewer/p0-codec/`에 둔다(`P0_CODEC_CACHE`로 변경 가능). cmake는 Python 격리 환경 안에 설치하며 Homebrew·전역 환경을 바꾸지 않는다. `MACOSX_DEPLOYMENT_TARGET=27.0`, release, arm64로 실행한다. 더 낮은 OS는 검증하지 않는다.

profile마다 별도 Cargo target과 복사된 binary를 사용해 feature가 섞이지 않게 한다. `baseline`, `charls`, `openjp2`, `openjpeg`, `combined`, `combined-c`의 실제 feature 정의는 Rust manifest가 기준이다. 비교에 실패한 사례가 있어도 다른 profile 실험을 끝까지 실행하며 마지막 exit는 fail이다. JSON의 fail/not-run을 pass로 바꾸지 않는다.

로컬 자료는 기존 공개 샘플 `local-data/`에서 읽는다. 실제 원본은 변경하지 않고, 보고서에는 fixture ID·공개 출처·해시·영상 형식만 기록한다. 경로를 포함할 수 있는 빌드 로그와 원시 실행 diagnostics는 캐시에 보관한다. 일반 Python 경고도 공개 보고서 대신 로컬 진단으로 분리한다.

## 검증 범위

- lossless: 독립 pydicom/참조 코덱 또는 명시 합성 golden의 전체 픽셀을 정확히 비교한다.
- lossy: 동일 압축 입력의 독립 decoder와 사전에 지정한 허용 차이를 비교하고 차이 크기를 보고한다. 압축 전 원본과 완전 일치를 주장하지 않는다.
- 저장 값과 Modality 값: 서로 다른 파일로 비교한다. 음수 intercept와 비단위 slope에서 변환을 한 번만 적용했는지 확인한다.
- multi-frame: 전체 디코딩과 개별 프레임을 독립 기대값에 비교한다. 빈 BOT, 허용된 다중 fragment, EOT와 손상 경계를 구분한다.
- 범위 밖 입력, 참조 decoder 부족, 변환/배열 배치 불일치를 별도 상태로 남긴다.
- 원본 SHA-256을 전후 대조한다. 실제 화면 표시·GPU·정식 T-03~T-05 합격은 not-run이다.

## 공식 근거

조회일 2026-09-30. 실제 채택 버전의 다운로드된 Cargo source와 최종 feature tree도 대조한다.

- [dicom-pixeldata 0.10.0 API](https://docs.rs/dicom-pixeldata/0.10.0/dicom_pixeldata/)
- [Transfer Syntax registry 0.10.0](https://docs.rs/dicom-transfer-syntax-registry/0.10.0/dicom_transfer_syntax_registry/)
- [ConvertOptions](https://docs.rs/dicom-pixeldata/0.10.0/dicom_pixeldata/struct.ConvertOptions.html)
- [pydicom 3.0.2 pixel_array](https://pydicom.github.io/pydicom/stable/reference/generated/pydicom.pixels.pixel_array.html)
- [DICOM PS3.5 2026d A.4](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/sect_A.4.html)

## 판단과 고정 후보

**dicom-rs 0.10.0 + baseline(native/deflate/jpeg/rle) + charls + openjpeg-sys를 제품 개발의 후보로 권고한다.** JPEG-LS·JPEG 2000의 정상 합성 사례와 공개 파일을 실제로 디코딩했다. 포함 여부의 최종 채택은 P0 전체 검토에서 정하고, 아래 제한을 해소하거나 capability로 차단한 뒤 제품 통합 시험으로 지원을 판정한다.

JPEG 2000의 두 backend는 이 자료에서 같은 사례 집계를 보였다. C OpenJPEG 후보를 권고한 근거는 실제 Mac의 정적 빌드 성공, 참조 대비 일부 lossy 자료의 최대 차이가 0(Rust 포트는 1)이었던 관찰이다. 참조 `pylibjpeg-openjpeg`와 **underlying OpenJPEG를 공유**하므로 이 차이는 독립 알고리즘에 대한 우월성의 증거가 아니다. 명시 합성 배열의 lossless golden은 별도로 독립 계산했다. `openjp2`와 `openjpeg-sys`를 동시에 켜는 조합은 실험에서 금지했다.

| 의존성 | 고정 버전 / 라이선스 | 실제 빌드 요구 사항 |
| --- | --- | --- |
| Rust | 1.98.1 | aarch64-apple-darwin, release, minimum OS 27.0 |
| dicom-object / pixeldata / transfer-syntax-registry | 각각 0.10.0 / MIT OR Apache-2.0 | direct default-features=false, 최종 transitive feature는 build JSON 기준 |
| jpeg-decoder / jpeg-encoder | 0.3.2 / MIT OR Apache-2.0; 0.7.1 / (MIT OR Apache-2.0) AND IJG | decoder 실험에도 encoder 의존성이 포함됨 |
| charls / charls-sys | Rust wrapper 0.4.2 / 2.4.5, MIT; bundled CharLS 2.4.2는 BSD-3-Clause | C++ 정적 빌드, CMake ≥3.13, 이번 실행은 4.4.3 |
| jpeg2k / openjp2 | 0.10.1 MIT/Apache-2.0 / 0.6.1 BSD-2-Clause | OpenJPEG Rust 포트, CMake 없이 빌드 |
| openjpeg-sys | 1.0.12 BSD-2-Clause; bundled OpenJPEG 2.5.3 | C 정적 빌드(cc), 실제 빌드에서 CMake 불필요, threads feature 꺼짐 |

최종 resolved package·license·feature 목록, binary SHA-256, 소스 파일별 SHA-256, minimum OS, 링크한 시스템 라이브러리는 `results/build-*.json`에 있다. 외부 codec dylib 링크는 없었다. 배포 시 필요한 notice 패키지 작성은 P5 작업이며 여기서 완료했다고 판정하지 않는다.

## 결과 해석

각 profile은 공개 331개 + 합성 50개(정상 42, 의도적 손상 8), 총 **381개**를 같은 정책으로 비교한다. 공개 자료의 라이선스는 upstream 저장소 MIT/BSD-2 기준으로 기록했고 개별 원본의 재배포 권한은 확정하지 않았다. 원본은 Git에 넣지 않는다. 합성 DICOM과 golden도 캐시에 생성하며 저장소에는 생성기와 해시 manifest를 기록한다.

최종 profile 집계와 Transfer Syntax별 표는 아래에 기록한다. `pass`는 해당 사례의 적용 가능한 비교가 일치했다는 뜻이며 손상 입력의 올바른 거부도 포함한다. `not-applicable`은 Pixel Data 없음, 제외한 HTJ2K·비영상 등 보고서의 개별 사유를 따른다. 전체 합격률로 제품 지원을 추정하지 않는다.

| Profile / 추가 feature | pass | fail | not-run | not-applicable |
| --- | ---: | ---: | ---: | ---: |
| baseline: native/deflate/jpeg/rle | 253 | 59 | 10 | 59 |
| charls: baseline + charls | 264 | 53 | 5 | 59 |
| openjp2: baseline + openjp2 | 273 | 39 | 10 | 59 |
| openjpeg: baseline + openjpeg-sys | 273 | 39 | 10 | 59 |
| combined: baseline + charls + openjp2 | 284 | 33 | 5 | 59 |
| combined-c: baseline + charls + openjpeg-sys | 284 | 33 | 5 | 59 |

최종 권고 조합 [combined-c.json](results/combined-c.json)의 TS별 사례 상태다. UID는 `1.2.840.10008.1.2` 뒤 suffix로 표시한다. 손상 입력과 픽셀 표현·색 변환을 포함하므로 아래 fail을 해당 codec의 모든 입력 실패로 해석하지 않는다.

| Transfer Syntax / suffix | pass | fail | not-run | not-applicable |
| --- | ---: | ---: | ---: | ---: |
| Implicit VR LE / 없음 | 8 | 2 | 0 | 7 |
| Explicit VR LE / .1 | 201 | 10 | 2 | 22 |
| Deflated Explicit VR LE / .1.99 | 5 | 2 | 0 | 0 |
| Explicit VR BE / .2 | 15 | 3 | 0 | 6 |
| JPEG Baseline / .4.50 | 11 | 3 | 1 | 0 |
| JPEG Extended / .4.51 | 0 | 1 | 1 | 0 |
| JPEG Lossless SV1 / .4.70 | 4 | 0 | 0 | 1 |
| JPEG-LS lossless / .4.80 | 7 | 7 | 0 | 0 |
| JPEG-LS near-lossless / .4.81 | 4 | 0 | 0 | 0 |
| JPEG 2000 lossless / .4.90 | 13 | 3 | 0 | 3 |
| JPEG 2000 lossy / .4.91 | 7 | 0 | 1 | 0 |
| RLE / .5 | 9 | 2 | 0 | 6 |
| 기타·TS 없음 (제외 근거는 JSON) | 0 | 0 | 0 | 14 |

권고 조합의 not-run 5건: `public-176-c425608e2fcd`, `public-177-b1fd9301d9d0`, `public-190-a3f26c279dd2`는 독립 decoder 오류; `public-308-c8798b8abf8a`는 참조 출력 256 MiB 한도; `public-309-0a4c3aa02d1b`는 FG Modality oracle 미구현이다. 마지막 사례의 stored 524,288개와 전체·selected frame 검사 4개는 pass다. 이 목록의 원본 파일명·경로·Instance UID는 공개 보고서에 넣지 않았다.

## 픽셀 변환 호출 규칙과 제한

실험은 `decode_pixel_data()` 또는 0기반 `decode_pixel_data_frame(N)` 뒤 `to_vec_with_options::<f64>(&options)`를 호출한다. 저장 값 경로는 `ModalityLutOption::None`, Modality 경로는 `ModalityLutOption::Default`, 둘 다 `VoiLutOption::Identity`다. None으로 얻은 upstream 배열을 이미 정규화된 DICOM 저장 값이라고 가정하면 안 된다. 제품에서 유효 비트와 부호를 정확히 정규화하고, Modality 적용 여부를 명시해 rescale을 한 번만 적용해야 한다. VOI와 극성·표시는 이후 별도 단계다.

| 사례 / 관찰 | 제품 구현에 필요한 조치 |
| --- | --- |
| signed 8비트 저장 값 최대 차이 256, sign-extension 없는 signed 12비트 4096, unsigned 12비트 unused high bits 61440; 같은 합성 Modality는 일치 | raw 저장 값의 Bits Stored 마스킹·부호 정규화, 저장 값과 Modality 경로 별도 검증 |
| RGB planar=1, 일부 RGB/YBR·Palette 공개 사례 오류 또는 불일치 | 배열 배치·색 변환 단계 명시, T-05 독립 픽셀 및 실제 화면 검증 |
| 정상 BOT/EOT·다중 fragment+BOT 사례는 일치하나 빈 BOT의 다중 fragment JPEG-LS/J2K는 실패 | 프레임 경계 분석과 decoder 전달 방식 보완 |
| 손상 BOT/EOT·선언 frame count 수락; 전체 오류여도 직접 frame 0 요청은 수락할 수 있음 | 전체·개별 프레임 모두 구조 검증, 모호한 경계 거부 |
| JPEG Extended 공개 사례에서 참조 성공·Rust 오류, 다른 사례는 참조 오류 | Extended를 별도 검증하고 capability를 제한 |
| public-316-28c4a61022d7: stored 정확, identity Modality 최대 차이 56976; public-328은 Modality LUT 포함 불일치 | 변환 원인 조사와 별도 회귀 사례; 성공한 rescale 합성을 전체 변환 지원으로 확대하지 않음 |
| Shared/PerFrame PixelValueTransformationSequence 존재 | 이 runner의 FG Modality oracle은 not-run; stored·프레임 검사는 유지. Enhanced 제품 해석은 v0.2 후보 |

lossless 저장 값 비교는 오차 0, lossy는 참조 decoder 대비 최대 차이 1이다. YBR→RGB 비교는 선언한 최대 차이 2를 별도 표시하고, 소스 YBR 저장 값이 관찰 불가한 lossless 사례의 raw 정확성은 not-run으로 남긴다. Modality는 decoder 오차×|slope|에 F64 산술 허용치 `max(1e-6, max_abs(expected)*1e-9)`를 합산하며 각 항목을 기록한다. 합성 배열·허용치를 실패에 맞춰 바꾸지 않았다.

입력 512 MiB, 선언 F64 domain 256 MiB, 10,000 frame 및 8/16비트 metadata guard는 실험용이다. Bits Stored 범위를 변환 전에 검증해 비정상 LUT 과다 할당 경로를 막았다. **parser의 deflate 확장, codec codestream 내부 할당 또는 전체 프로세스 메모리 한도는 보장하지 않는다.** T-13은 제품에서 별도 구현·검증해야 한다.

## 프레임 단위 메모리 관찰

전체 실행 후 재현 명령(새 결과는 캐시에 저장):

```sh
P0_CODEC_RUN_CACHE="${P0_CODEC_CACHE:-$HOME/Library/Caches/dicom-viewer/p0-codec}"
"$P0_CODEC_RUN_CACHE/venv/bin/python" experiments/p0-codec/bench_memory.py \
  --binary "$P0_CODEC_RUN_CACHE/p0-codec-combined-c" \
  --work-dir "$P0_CODEC_RUN_CACHE/memory-repeat" --report "$P0_CODEC_RUN_CACHE/memory-repeat.json"
```

`bench_memory.py`는 `(x+2*y+17*f)%4096` 수식의 RLE 32×512×512 uint16 자료를 생성하고 독립 readback·전 픽셀·원본 해시를 확인했다. `combined-c` 별도 프로세스 3회씩 실행에서 전체 decode peak RSS는 **166.86~168.84 MiB**, 마지막 한 frame은 **20.63~20.64 MiB**였다. 원래 decoded uint16은 전체 16 MiB, 한 frame 0.5 MiB다. RSS에는 parse·f64 변환·출력 파일 I/O·codec이 포함된다. 모든 6회 픽셀 비교는 pass이며 [memory.json](results/memory.json)에 binary·generator hash가 있다. RLE 한 자료의 프로세스 관찰로 긴 cine·동시 요청·캐시 예산·실제 표시 성능을 판정하지 않는다.

## 검증 증거와 다음 작업

[verification.json](results/verification.json)은 최종 소스·binary·보고서 해시 대조, 원본 전후 및 목록 해시 일치, profile 간 합성 해시 동일 여부, 실제 명령 결과를 모은다. Rust fmt/test/clippy, 참조 비교기의 신뢰 경계 시험, Python/Bash 구문 검사와 6개 release build를 수행했다. 전체 비교 명령은 관찰된 fail/not-run 때문에 **exit 1**이며 이를 합격으로 바꾸지 않았다.

P0-CODEC 조사 결과를 [P0 계획](../../docs/implementation/P0-tech-data.md)에 연결한다. 다음은 P0-DATA 부족 자료·합성 계획 보완, P0 전체 독립 검토, OQ 결정과 FFI 계약 검토다. 앱/GPU/FFI 통합, 정식 T-03~T-05·T-13, 긴 cine와 하위 OS 시험은 not-run이다.
