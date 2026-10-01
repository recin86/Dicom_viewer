# P1 컬러·코덱 경계 준비

2026-10-01 · Task `P1-ADAPTER-PREP-20261001` · Codex/root · **독립 조사·시험 준비 완료, 제품 구현 대기**.

사용자 요청: 다음 단계 진행. 기준은 `codex/p1-foundation`의 `c68c9208`와 동결된 DISPLAY-1 미커밋 변경이다. DISPLAY-1의 마지막 실제 UI 회귀는 Mac 잠금으로 `not-run`이다. 의존 제품 구현과 완료 판정은 해당 회귀 확인 뒤 진행하고, 독립 조사와 fixture 준비는 AGENTS의 단계 의존성 규칙에 따라 먼저 수행한다.

## 목적과 의존성

[P1 계획](P1-single-frame.md)의 묶음 4를 작은 검증 단위로 나눈다. 먼저 기존 P0의 planar·RGB/YBR/Palette 실패 원인을 현재 native adapter와 대조한다. 압축 프레임 경계·LUT는 별도 작업으로 남기며 fixture 준비를 앱 지원으로 보고하지 않는다. 연결 기준은 docs/03의 컬러 변환과 압축 경계, docs/04의 Rust RGBA8 계약, docs/06 T-03/T-05/T-11/T-13이다.

`PIXEL-1`·`DISPLAY-1` revision과 payload budget·source hash·Swift/GPU 수명은 보존한다. 이 준비 작업에서는 공개 API와 제품 소스를 바꾸지 않는다. 생성 자료는 별도 cache 디렉터리에 두고 기존 DISPLAY fixture 24개·manifest·검증 JSON을 변경하지 않는다. 원본과 P0 소스·결과는 동결한다.

## 작성권

| Task | 작성자 | 허용 범위 | 상태 |
| --- | --- | --- | --- |
| P1-ADAPTER-INVESTIGATE | dicom_core | 제품/실험 소스·기존 문서 읽기 전용 | 완료·작성권 반환 |
| P1-COLOR-FIXTURE-PREP | root | 신규 `scripts/prepare-color-fixtures.py`·`verify-color-fixtures.py`, 이 계획·중앙 진행 문서·신규 준비 결과 JSON | 준비 완료·미커밋 |
| P1-COLOR-PREP-REVIEW | dicom_reviewer | 신규 fixture writer·manifest·기준값·계획 읽기 전용 | 완료·필수 지적 반영·열린 결함0 |
| P1-DISPLAY-UI-RESUME | root | 기존 표시 소스 보존, 잠금 해제 후 실제 UI·결과 기록 | Mac 잠금 해제 대기 |

## 준비 완료 기준

- literal 색 패치와 정확한 pixel layout/길이·형식·hash를 갖춘 결정적 Part10 fixture를 만든다. 정상과 손상 입력의 기대 상태를 분리한다.
- 별도 pydicom readback으로 정상 stored/RGB 기대값과 실제 파일 metadata를 확인한다. 제품 Rust adapter 호출을 oracle로 사용하지 않는다.
- 반복 생성의 fixture hash가 같고 기존 DISPLAY snapshot과 P0가 유지되는지 확인한다.
- 독립 reviewer가 fixture/expectation/계획을 대조한다. 제품·FFI·Metal·실제 UI 결과는 해당 구현 전까지 `not-run`이다.

## 다음 순서

DISPLAY-1 실제 파일 선택/상태 복구 회귀와 독립 리뷰를 마무리하고 해당 변경을 커밋한다. 이후 조사 결과를 바탕으로 작은 컬러 adapter 과업의 작성권·공유 계약·합격 기준을 등록하고 구현한다. 전체 codec/LUT/US·X-ray 지원을 한 번에 완료한 것으로 처리하지 않는다.

후속 사용자 지시 "일단 다음단계진행"에 따라 [P1-COLOR-20261001](P1-native-color.md)에서 SC컬러 producer와 자동FFI/Metal시험을 먼저 시작했다. 검증된 불변RGBA8/예산/descriptor계약에 기대며 실제NSOpenPanel/presentation회귀와 독립적인 경로다. 위 순서는 당시 인수인계이고 현재 제품 작성권/의존성은 새 과업을 따른다. UI완료와전체지원판정은여전히보류한다.

## 실제 준비 검증

최종 manifest revision2의 별도 `$P1_CACHE/color-fixtures-v2`와 `color-fixtures-v2-repeat`에 26개를 생성했다. 정상 후보11은 SC RGB planar0/1·LE/BE/implicit, SC YBR_FULL·422, US RGB와 SC/US dense16 Palette다. US nativeYBR3개는 미지원 후보이자 generic raw색 readback 전용이다. 나머지 손상/범위제외12는 layout/길이/signed/rescale·palette descriptor/data 및 초기 제외 표현이다. 정상11과 raw전용3의 stored/RGB/RGBA literal은 전 픽셀 일치했다. negative15의 metadata 독립 기대 조건을 확인했으며 제품 거부는 `not-run`이다.

실제 명령:

```sh
python3 scripts/prepare-color-fixtures.py "$P1_CACHE/color-fixtures-v2"
python3 scripts/prepare-color-fixtures.py "$P1_CACHE/color-fixtures-v2-repeat"
"$REFERENCE_VENV/bin/python" scripts/verify-color-fixtures.py \
  "$P1_CACHE/color-fixtures-v2" "$P1_CACHE/color-fixtures-v2-repeat" \
  "$P1_CACHE/color-preparation.json"
```

`P1_CACHE`는 기존 p1 cache, `REFERENCE_VENV`는 기존 p0-codec cache의 venv다. Python3.12.13/pydicom3.0.2/numpy2.5.3에서 preparation26 pass/0 fail·정상11과raw전용3 literal readback·반복26 byte 일치. Python AST와 `git diff --check` pass다. 잘못된 RGB 기대값과 변경된 DICOM byte를 각각 별도 cache에 주입한 검증기 시험2건은 기대한 check와 exit1을 기록했다. 이는 실패를 정상적으로 검출한 preparation 시험이다. 동일 source35/generated3/기존fixture24 manifest는 DISPLAY snapshot과 일치하고 P0 tracked diff는 비어 있다.

처음 US planar0 규칙을 generic prose에서 옮긴 뒤 planar표만 보고0/1을 정상 후보로 분류했으나, 독립 reviewer가 C.8.5.6.1.2의 nativeTS/Photometric 제약을 추가 확인했다. USYBR3개를 정상제품기준에서 제외하고 rawreadback전용으로 수정했다. USpalette16 index도16bit로 보완했고 implicitVR의 PixelData reader추정OW를 명시OB와 혼동한 검증기1건을 수정했다. 최종26 pass에 앞선 실패/분류정정을 숨기지 않는다. source2·manifest·fixture ID/형식/hash·readback·검증기 실패 주입은 [P1-color-preparation.json](results/P1-color-preparation.json)에 기록한다. raw 생성물은 cache-only이며 제품 소스·공개 API·지원판정은 변경하지 않았다.

## 조사 결과와 첫 구현 계약

읽기 전용 core 조사: P0 `combined-c`의 33 fail은 저장 값 정규화11·컬러/배치12·정상 빈 BOT 다중 fragment2·손상 구조 수락5·JPEG Extended1·Modality2로 분류했다. 이는 관찰된 계약별 분류이며 모든 근본 원인이 확정된 것은 아니다. 기존 결과를 재실행하지 않았고 284/33/5/59와 not-run 이유는 그대로 보존한다. native planar1 실패6건과 native YBR422 실패1건을 먼저 겨냥한다.

첫 제품 substep은 단일 SC의 8비트 RGB planar0/1·YBR_FULL·YBR_FULL_422다. core의 `native.rs`와 신규 `native_color.rs`·`lib.rs`에서 private helper를 추가하고 공개 타입/revision·RGBA8 alpha255·mask 없음·source hash·예산/owner를 보존할 수 있다. 의존성 추가는 예상하지 않는다. 컬러의 window/반전은 비활성화하고 단위는 unknown이다. odd-width422·고비트 컬러·ICC·필요한 미구현 color transform·압축·Palette·US는 명시 거부하며, Palette/US는 독립 fixture로 후속 substep을 준비한다. Rust 준비→FFI/C copy→Swift owned→Metal literal 비교는 구현 때 실제 실행한다.

## 최종 검토와 인수인계

독립 reviewer는 최종source2·manifestrev2·fixture26/repeat26·readback/controls report 해시와 내용을 직접 대조했다. 별도 read-only pydicom3.0.2와 BT.601 역변환·palette index clamp 계산으로 raw색14종의 stored/RGB/RGBA 및 negative15종의 실제 metadata를 확인했다. US제약 지적을 반영한 뒤 열린 필수결함0·남은 준비검토항목0이다. 검증CLI 재실행·fixture재생성·빌드·앱기동·파일수정은 하지 않았다. DISPLAY35/generated3/fixture24와 P0동결도 별도 확인했다.

**독립 준비만 완료.** COLOR제품/adapter거부/Metal/사용자UI와 DISPLAY최종UI는 `not-run`이다. Mac잠금은 재시도3회 모두 유지됐고 잠금해제요청은 답변대기다. 새 준비4파일과 중앙문서 변경은 미커밋이며 기존DISPLAY미커밋 변경과 구분한다. 실행 중인 작성 작업은 없고 core/reviewer 작성권을 반환했다. 다음은 잠금해제된GUI에서 DISPLAY실제회귀→review/commit, 그 뒤 위 첫 컬러substep의 작성권과 통합시험을 등록하는 순서다. push는 없다.

[DICOM PS3.3 2026d Image Pixel](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.3.html)과 [US Image](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.5.6.html)를 2026-10-01 조회했다. native422는 nominal spp3이어도 `rows×columns×2` bytes, `Y1,Y2,Cb,Cr`이고 planar0이다. US전용표 C.8-23의 YBR_FULL uncompressed0/1은 planar조건이지만 **C.8.5.6.1.2는 native spp>1의 Photometric=RGB를 요구**한다. 같은 판 genericprose/planar표와 차이가 있어 US nativeYBR은 정상제품수락에서 제외하고 제한/표준충돌용 rawreadback자료로 보존한다. RLE/다른압축의 규칙을 native에 확대하지 않는다. US dense16palette index는 표 C.8-20과 C.8.5.6.1.14/15에 맞게 unsigned16/BitsStored16/HighBit15다. 파일은 pixel-module 검증용 최소Part10이며 전체IOD적합성 증거가 아니다.
