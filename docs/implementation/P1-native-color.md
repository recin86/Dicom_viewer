# P1 native SC 컬러 변환

2026-10-01 · Task `P1-COLOR-20261001` · Codex/root · **자동 구현·시험·독립 검토 완료 · 실제 UI not-run**.

사용자 요청: 화면 검증을 기다리지 않고 일단 다음 단계 진행. 기준 `codex/p1-foundation`/`c68c9208`와 기존 DISPLAY/컬러준비 미커밋 변경을 보존한다. 이미 자동 검증한 PIXEL-1/DISPLAY-1의 RGBA8·source revision·수명/예산 계약으로 SC 컬러 producer와 자동 소비자 시험을 진행한다. 기존 NSOpenPanel/presentation 회귀는 이 private 색 변환의 수치 의존성이 아니므로 병행 가능한 작업으로 분리했다. 실제 UI 완료·전체 P1 지원 판정은 기존 `not-run`을 유지한다. 이전 준비 계획의 UI 후 구현 순서는 이번 사용자 지시에 따라 변경하며 승인 질문을 반복하지 않는다.

## 범위와 공유 계약

docs/03 컬러 규칙, docs/04 PIXEL-1·DISPLAY-1과 docs/06 T-03/T-05/T-11/T-13·FR-03/QR-01에 연결한다. 첫 substep은 native 단일 SC의 unsigned8 RGB planar0/1, YBR_FULL planar0/1, even-width YBR_FULL_422 planar0다. LE/implicitLE 및 검증 가능한 BE OB를 유지한다. `rows×columns×2`인422의 길이를 nominal spp3과 구분하고 `Y1,Y2,Cb,Cr`를 같은 행에서 확장한다. Rust가 한 번 색 변환한 row-major RGBA8/alpha255/mask없음/DisplayColor를 반환하며 Swift는 YBR 변환을 다시 하지 않는다.

공개 타입/revision·준비API·32MiB opened handle 제한·동일입력SHA256·할당 전 payload 예약·close/evict/owner 해제를 보존한다. 의존성 추가와 shader/제품UI 변경은 예상하지 않는다. Gray32 변환은 보존한다. 미지원 SOP/US/Palette·고비트컬러·odd-width422·ICC·필요한 color rescale/VOI/padding·압축/Enhanced/다중frame은 명시 거부한다. 새 기능을 전체 codec 지원으로 보고하지 않는다.

## 작성권

| Task | 작성자 | 허용 수정 범위 | 상태 |
| --- | --- | --- | --- |
| P1-COLOR-CORE | dicom_core | core `native.rs`, 신규 `native_color.rs`, `lib.rs` 및 해당 파일의 Rust 시험 | 완료·작성권 반환 |
| P1-COLOR-CHECKS | macos_app | 신규 `macos/Sources/ViewerColorChecks/**`만 | 완료·작성권 반환 |
| P1-COLOR-INTEGRATE | root | FFI 필요 변경, Package/scripts·공유 fixture 필요 확장·중앙/API/지원 문서·결과 JSON | 통합 시험 완료 |
| P1-COLOR-REVIEW | dicom_reviewer | 최종 source/generated/fixture/report/binary/문서 읽기 전용 | 완료·필수 결함 0 |

## 구현 전 기대값과 합격 기준

[준비 결과](results/P1-color-preparation.json)의 manifestrev2/source2와26 cache-only fixture를 기반으로한다. 최초accept7종(SC RGB4, SC YBR_FULL2, SC4221)은 독립 literal RGBA와 정확 일치(RGB) 또는채널≤1(YBR)하고 size/stride/mask/descriptor/source hash가 유지돼야한다. 나머지19종은 초기지원제외/손상 조건대로 structured error를 반환하고 live예산/cached/active가 복구되어야한다. 정상·실패를 다른 file path/PHI를 포함한 raw 오류로 기록하지 않는다.

Swift CLI는 실제 native prepare→FFI handle→C copy→owned RGBA→Metal upload/offscreen 경로를 실행한다. nearest/linear와 임의 window/사용자반전에도 이미정규화된RGB가 변하지 않는지 확인하고, close 뒤 handle/copy/GPU 참조가 유효한지·마지막 참조 후 예산이 해제되는지 검사한다. source hash와 원본전후 hash를 대조한다. Rust fmt/clippy/단위시험·debug/release 공통check를 최종수정상태에서실행하고 독립 reviewer로 대조한다. 실제 drawable·사용자NSOpenPanel/UI시험은 Mac잠금 때문에별도not-run이며 자동Metal과 구분한다.

## 종료 기록

- core는 `native.rs`·신규 `native_color.rs`·`lib.rs`를 변경했다. root는 Package target·공통 check 경로·문서·결과를 연결하고 app은 신규 `ViewerColorChecks/ColorChecks.swift`를 작성했다. 기존 FFI·Bridge·Rendering·App과 공개 선언·의존성은 이번에 변경하지 않았다.
- `bash scripts/check.sh`와 `bash scripts/check.sh --release` 모두 exit0: fmt/clippy, Rust core38+FFI7, PIXEL18, DISPLAY26, COLOR29, bootstrap·원본 hash 보존 pass. 컬러 정상7종/거부19종, nearest/linear·2배 선형 보간·window/invert 무변화, source revision, 확장 RGBA 예산과 close/copy/GPU 마지막 owner를 확인했다.
- [최신 결과](results/P1-native-color.json): source39·generated3·fixture50·binary8·log2·report8. 생성 바인딩3개와 준비 source2/manifest는 이전과 같다. 기존 DISPLAY35개 중 core lib/native·Package/check 4개만 바뀌었고 나머지31개·fixture24는 보존했다. 양쪽 bundle strict/deep ad-hoc 서명, 실행파일8개 arm64/minos27/static Rust 직접 확인. raw 로그는 ignored 캐시에만 보관한다.
- 독립 reviewer가 최종 코드를 읽고 YBR 전체 8-bit 조합을 pinned pydicom과 별도로 비교했다(최대 채널차1). source39·generated3·manifest2·fixture50·binary8·log2·report8의 크기/hash와 embedded JSON을 별도로 대조했고 필수 수정 결함0으로 좁은 COLOR-1 자동 범위 완료를 판정했다. 재빌드·앱/검증CLI 실행·fixture 생성·파일 수정은 하지 않았다. 기존 DISPLAY/P0 JSON은 당시 snapshot이며 현재 binary와 일치한다고 주장하지 않는다.
- 최신 실제 NSOpenPanel/Ready·실패 후 이전 사용자 설정 복구·actual drawable/RGB controls는 Mac 잠금 때문에 not-run이다. 전체 P1·앱 지원 완료 판정을 보류하며 US·Palette·압축/LUT/Enhanced·전체 자원/성능·모니터 보정은 후속이다.
- 코드 작성권 모두 root에 반환. 사용자 요청으로 앞선 DISPLAY/준비와 함께 후속 로컬 커밋에 포함했으며 최신 hash는 `git log -1`로 확인한다. push 없음. 결과 JSON의 uncommitted/baseline 표시는 시험 당시 snapshot 상태다. 다음은 GUI를 사용할 수 있을 때 최신 debug/release `--ui`와 실제 파일 선택/오류 복구를 검증하고, 독립적인 후속 과업으로 Palette16 LUT adapter를 진행한다. US IOD·압축/frame 경계는 별도 과업으로 유지한다.
