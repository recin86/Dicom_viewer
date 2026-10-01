# P1 native 단일 프레임 표시

2026-10-01 · Task `P1-DISPLAY-20261001` · Codex/root · **최종 실제 UI 검증 대기, 완료 판정 보류**.

사용자 요청: 완료한 코드를 커밋하고 다음 단계 진행. 골격·픽셀 계약을 `c68c9208be771e366fe0824d0a7a8291eb679597`으로 커밋했다. 이 커밋에서 working tree clean을 확인했으며 원격 push는 하지 않았다. 이전 결과 JSON은 검증 당시 스냅샷으로 보존한다.

## 범위와 기준

P1 묶음 3의 실제 native 파일 열기→Rust 표시 설명→Swift 소유 버퍼→Metal 한 프레임 표시를 구현한다. 회색조 LINEAR/LINEAR_EXACT/SIGMOID·기본 극성·사용자 반전·표시 비율·fit/기본 조작, 제한된 RGB SC 표시를 연결한다. 압축·Enhanced·다중 프레임·LUT·폴더/시리즈 탐색·측정은 후속이며 지원 판정을 확대하지 않는다.

기준: docs/03의 VOI·극성·padding·aspect, docs/04의 immutable payload와 source/request generation·좌표, docs/05의 Loading/Ready/Failed, docs/06 T-04/T-11/T-12/T-16/T-21 일부. 관련 ADR 0002 채택을 보존하고 ADR 0003은 이번 실제 Metal 검증 후 채택 여부를 정한다.

## 작성권

| Task | 작성자 | 파일 | 상태 |
| --- | --- | --- | --- |
| P1-DISPLAY-CORE | dicom_core | crates/viewer-core/src/**, core Cargo.toml | done, main에 반환 |
| P1-DISPLAY-APP | macos_app | macos/Sources/ViewerApp/**, ViewerRendering/**, ViewerDisplayChecks/** | 소스 작성 완료, 마지막 UI 회귀 대기 |
| P1-DISPLAY-BRIDGE | root | viewer-ffi/**, ViewerBridge/**, workspace/lock·Package·scripts·fixture·문서·결과 | 통합/자동 검증 완료, UI 대기 |
| P1-DISPLAY-REVIEW | dicom_reviewer | 읽기 전용 최종 검토 | 조건부 검토 반환, 실제 UI 완료 보류 |

## DISPLAY-1 공유 계약

PIXEL-1의 형식·길이·예산·C copy를 유지한다. 별도 immutable DisplayInfo를 추가하며 revision=1, source_revision은 동일 opened bytes의 SHA-256, frame_index=0이다. VOI window는 center/width F64와 Linear/LinearExact/Sigmoid다. windows 목록·default_window optional·automatic_window·inverted·pixel_height_over_width·aspect_source/estimated·unit·safe diagnostics·can_window를 Rust에서 해석한다. Swift는 DICOM 태그를 다시 읽지 않는다.

낡은 파일 요청은 viewport generation으로 차단하며 취소된 worker는 끝날 수 있어도 새 영상·라벨을 덮지 않는다. 각 준비는 별도 session으로 격리하고 완료/실패/폐기 시 close한다. Swift 복사본·GPU 리소스는 command buffer 완료까지 유지하고 사용 중 texture/buffer를 덮어쓰지 않는다. 큰 준비·복사·GPU upload/offscreen readback은 백그라운드로 실행한다.

작은 CPU 기준 RGBA는 최대 16,384 pixels/64 KiB로 제한한 검증 전용 API로 제공한다. 제품 표시에는 기존 소유 픽셀 버퍼와 Metal을 사용한다. CPU/Metal gray 출력 차이는 채널당 1 이하, mask=0은 반전과 무관한 black, RGB는 byte patch와 일치해야 한다.

## 구현과 검증

환경: Apple M5·16 GiB·macOS 27.0.1 (26A434), arm64, Rust1.98.1·Swift6.4·UniFFI0.32.2·dicom-rs0.10.0, minimum OS27.0. Xcode 없이 runtime Metal compile을 사용한다. sha2 0.10.9로 동일 입력의 revision을 계산하며 다른 기존 lock 버전은 변경하지 않았다.

| 최종 수정 후 명령/경로 | 실제 결과 | 판정 |
| --- | --- | --- |
| `bash scripts/check.sh` | fmt/clippy, Rust core28+FFI7, PIXEL18, Metal26, bootstrap, 원본 hash 보존 | pass |
| `bash scripts/check.sh --release` | 같은 계약과 35+18+26 시험, release build·정적 링크·bundle strict 서명 확인 | pass |
| 명암·mask·RGB | LE/BE/implicit, 3종 VOI/반전·uniform/allpadding·RGB, CPU+독립 literal과 GPU 전 픽셀 차이≤1. nearest/linear 비교 및 padding 이웃 가중 직접 기대값 | pass |
| source/aspect/상태/수명 | 동일 SHA/source revision, spacing2:1·fit/pan/zoom/Retina roundtrip, 공유 generation/history 정책, 실제 upload 뒤 Swift owner/GPU 완료 수명 | pass (정책/CLI 범위) |
| 실패 입력 | invalid file/override window, finite F64이지만 GPU 표현 불가 VOI, 실제 native20,000×1 준비/복사 뒤 texture cap 사전거부 | pass |
| 마지막 `--ui`·실제 파일 선택 창·이전 표시 상태 복구 | 마지막 재표시 수정 이후 Mac 잠금으로 미실행, 사용자에게 잠금 해제 요청 | **not-run** |

합성 Part10 24개는 cache-only이며 stdlib writer의 literal stored 값과 수식 기대값을 사용한다. manifest는 ID·format·size/hash를 보존한다. 결과와 코드/생성물/binary/log hash는 [P1-native-display.json](results/P1-native-display.json)에 기록한다. raw log는 ignored `~/Library/Caches/dicom-viewer/p1/`의 `display-check-debug.log`, `display-check-release.log`다. 실제 지원 범위는 좁은 native CT/MR/SC 회색조와 RGB SC이며 압축·Enhanced·다중 프레임·LUT를 명시 거부한다.

독립 reviewer의 조건부 최종 반환: 열린 필수 소스 결함0, source35/generated3/fixture24/binary6/log2/report6의 크기·해시·실제 JSON 대조 일치. pydicom3.0.2로13종 stored/표시 tag를 별도 read-only 파싱했고 두 bundle의 서명·arm64/minos27/static Rust를 직접 확인했다. 재빌드·앱 실행·fixture 생성은 수행하지 않았다. 마지막 실제 UI 회귀가 not-run이므로 DISPLAY-1 완료를 보류한다.

## 검토에서 수정한 문제와 남은 회귀

LINEAR 폭이1에 가까울 때 Float 반올림으로 threshold가 되는 문제, SIGMOID 중간 곱셈/뺄셈 overflow를 수정하고 실제 GPU literal 시험을 추가했다. 실패한 후보가 이전 사용자 대비·반전·zoom/pan을 덮던 문제는 실제 표시 뒤 기록하는 전체 state history로 수정했다. stale failure/presentation은 generation과 upload identity로 차단한다. overlay/shutter·추정 비율 등의 안전한 제한 설명은 대비 상태와 별도 표시한다. popup 사용자 대비 항목과 실제 window의 선택도 일치시킨다.

초기 startup `--display-smoke-test`는 두 profile에서 실제 drawable3×2 presentation·마지막 창 종료 pass였다. 하지만 CUA의 실제 Command O→NSOpenPanel 선택에서 영상이 보이면서 Loading/disabled가 남는 별도 문제를 발견했다. resize로 첫 presentation을 버리던 guard를 수정한 뒤 startup 재시험은 pass였고, sheet 전환 중 one-shot drawable이 skipped되면 재시도가 없는 경로를 추가 확인했다. 최신 소스는 후보의 **presentedTime>0** 실제 callback까지 연속 재표시하며 Ready/Fail/새 요청/close 때 on-demand로 돌아간다. GPU 완료를 실제 presentation으로 대체하지 않는다. 이 마지막 수정의 수동 회귀는 Mac 잠금으로 아직 실행하지 못했다. 이전 startup pass를 최신 사용자 경로 pass로 취급하지 않는다.

`--trace-display`는 선택적인 stderr JSON 이벤트(load/candidate/submitted/gpuCompleted/presented/skipped/ready/stale)를 generation/revision/count만 포함해 기록한다. 경로·환자 값·raw 오류 이유는 넣지 않으며 기본 실행에서는 trace를 쓰지 않는다.

## 재개와 인수인계

1. Mac 잠금 해제 후 기존 검증 앱을 종료하고 최신 앱으로 `bash scripts/check.sh --ui`, `bash scripts/check.sh --release --ui`를 실행한다.
2. 실제 Command O→파일 선택 창에서 `display-exact.dcm`을 열고 Ready와 조작 활성화를 확인한다. 대비·반전·확대/이동 후 `display-unrenderable-window.dcm`의 실제 encode 실패에서 이전 영상·설정·label을 보존하는지 확인하고, 재시도 및 새 정상 파일을 연다.
3. `display-diagnostics.dcm`의 overlay/shutter 제한, `rgb.dcm`의 색/비활성 grayscale controls, resize/fit을 AX·screenshot/선택적 safe trace로 기록한다. 별도의 actual CUA 증거와 공유 정책 시험을 구분한다.
4. 최종 source/binary/fixture/log hash·독립 reviewer를 다시 대조해 묶음3 완료를 판정한다. 이어서 묶음4의 컬러/X-ray/US 및 codec/LUT adapter를 계획한다.

현재 HEAD는 선행 골격/픽셀 계약의 `c68c920`, 이번 표시 변경은 미커밋이다. push는 없다. core/app은 수정 대기 없이 main에 소스를 반환했으며 P0 실험·결과는 변경하지 않았다. 회전·측정/주석·전체 codec/parser/engine/RSS·성능·색/모니터 보정·P5 설치는 이번 합격 대상이 아니다.

후속 사용자 지시로 [native SC컬러 과업](P1-native-color.md)을 UI대기와독립적으로 시작했다. 이 문서의35개source/기존binary/결과JSON은 COLOR변경 전 역사적snapshot이다. 현재파일/새검증은후속컬러결과에서기록하며 이JSON의해시를새소스일치로주장하지않는다. DISPLAY실제UI회귀는not-run을유지한다.
