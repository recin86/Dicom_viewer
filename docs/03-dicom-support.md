# DICOM Viewer DICOM 지원 명세

이 문서는 어떤 DICOM을 표시하고 어떻게 해석할지 정의한다. 파일 파싱, 픽셀 디코딩, 프레임 의미 해석, 화면 표시와 측정은 각각 별도의 지원 단계다. 라이브러리가 파일을 읽었다는 사실만으로 앱이 해당 영상을 완전히 지원한다고 판정하지 않는다.

문서 버전 0.2 · 작성·검토일 2026-09-30 · 상태 검토·보완한 설계 초안. 아래 표는 개발 목표이며 **정식 앱 지원 합격 판정은 아직 없다**. 제한된 native 단일 프레임의 구현은 [P1 표시 기록](implementation/P1-native-display.md), 최신 SC 색 변환과 자동 시험은 [컬러 기록](implementation/P1-native-color.md)에 따로 둔다. v0.1은 앱 버전 제안이고, 문서 버전과 별개의 개념이다.

## 지원 상태 기록

실제 capability는 SOP Class UID, Transfer Syntax UID, 픽셀 표현, 프레임 의미, 필요한 변환 및 빌드에 포함된 decoder를 함께 확인한다. Modality 문자열만으로 허용하지 않는다.

| 상태 | 의미 | 사용자에게 제공하는 동작 |
| --- | --- | --- |
| 목표 | 아직 구현과 검증 전 | 개발 문서에서만 사용 |
| 검증됨 | 명시된 조합과 시험 자료에서 합격 | 검증 범위 안에서 정상 표시 |
| 부분 지원 | 가능한 기능과 제한을 구체적으로 확인 | 예를 들어 영상 표시 가능, 물리 측정 불가 |
| 메타데이터만 | 객체를 읽지만 영상 해석 또는 표시 불가 | 태그와 미지원 이유 표시 |
| 실패 | 손상, 잘못된 값 또는 자원 제한 | 실패 단계와 이유 표시 |

부분 지원은 빠진 필수 변환을 무시해 그럴듯한 이미지를 표시한다는 의미가 아니다. 픽셀 값을 올바르게 표시할 수 없는 조합은 영상 표시를 차단한다.

## SOP Class별 목표

| 대상 | 목표 시점 | 표시와 탐색 | 제한 및 시험 조건 |
| --- | --- | --- | --- |
| CT Image Storage | v0.1 | 단일 프레임 인스턴스의 공간 스택 | signed/unsigned, rescale, 다양한 orientation 시험 |
| MR Image Storage | v0.1 | 단일 프레임 인스턴스의 스택 또는 그룹 목록 | 시간, echo, diffusion 관련 차원이 섞인 경우 무조건 하나의 볼륨으로 합치지 않음 |
| Computed Radiography Image Storage | v0.1 | 회색조 정지 영상 | 내장 LUT, 극성, 간격 정보 시험 |
| Digital X-Ray Image Storage for Presentation | v0.1 | 회색조 정지 영상 | 해당 IOD의 표시 의미와 보정 근거 시험 |
| Ultrasound Image Storage | v0.1 | 회색조 또는 컬러 정지 영상 | 지원 픽셀 및 압축 조합에 한정 |
| Ultrasound Multi-frame Image Storage | v0.1 | 프레임 이동과 cine | 독립 프레임 디코딩 가능한 기본 코덱 조합부터 시험 |
| Secondary Capture Image Storage | v0.1 보조 목표 | 지원 픽셀의 정지 영상 | 픽셀 값에 HU나 환자 공간 의미를 임의 부여하지 않음 |
| Enhanced CT 및 Enhanced MR | v0.2 후보 | 프레임별 메타데이터와 다차원 탐색 | Functional Groups와 Dimension Index 처리 완료 후 지원 |
| DX for Processing 및 제조사 후처리 의존 자료 | 후속 후보 | 현재는 메타데이터 조회 | 필요한 처리 검증 전에는 완성된 X-ray로 표시하지 않음 |
| Retired US SOP Class, Multi-frame SC | P0에서 수요 확인 | 명시적으로 추가한 클래스만 지원 | 비슷한 이름의 SOP Class에 지원을 자동 확대하지 않음 |
| SR, SEG, RT, PET, WSI, Encapsulated PDF, Presentation State | 초기 범위 밖 | 메타데이터 조회 가능한 경우만 목록화 | 다른 영상의 주석이나 표시 상태로 자동 적용하지 않음 |

정확한 UID는 구현 시 표준 dictionary의 상수를 사용하고 테스트 manifest에 실제 값으로 기록한다. 위 SOP 이름은 지원 범위를 설명하기 위한 분류이며 포괄적인 conformance statement가 아니다.

## Transfer Syntax 목표

아래 라이브러리 정보는 2026-09-30에 확인한 dicom-transfer-syntax-registry 0.10.0 문서를 기준으로 한다. 채택할 실제 버전과 feature 조합은 P0에서 고정한다.

| 형식 | 라이브러리의 문서상 경로 | 앱 계획 |
| --- | --- | --- |
| Implicit VR Little Endian | 기본 지원 | v0.1 필수 시험 |
| Explicit VR Little Endian | 기본 지원 | v0.1 필수 시험 |
| Explicit VR Big Endian | 기본 지원 | v0.1 필수 시험, endian 회귀 시험 |
| Deflated Explicit VR Little Endian | deflate | v0.1 필수 시험 |
| RLE Lossless | rle | v0.1 필수 시험 |
| JPEG Baseline, Extended, Lossless | jpeg | v0.1 목표, 각각 별도 사례로 검증. P0-CODEC에서 JPEG Extended 공개 사례는 pass 0·fail 1·not-run 1이라 별도 검증 전 capability를 제한 |
| JPEG-LS lossless 및 near-lossless | charls | v0.1 대상 (OQ-03, P0 종료). 빈 BOT 다중 fragment 실패 등 [P0-CODEC](../experiments/p0-codec/README.md) 제한 해소 후 지원 판정 |
| JPEG 2000 | openjpeg-sys (C OpenJPEG 2.5.3 정적 빌드); openjp2는 사용하지 않음 | v0.1 대상 (OQ-03, P0 종료). 같은 조건으로 지원 판정 |
| HTJ2K | 레지스트리 표에 openjp2 또는 openjpeg-sys 경로가 있으나 대상 빌드의 실제 동작은 미검증 | v0.1 기본 범위에서 제외; 후속 평가 |
| JPEG XL | jxl-oxide 디코딩 경로가 문서화됨 | v0.1 기본 범위에서 제외; 후속 평가 |
| MPEG/H.264/H.265 기반 video | 이번 앱의 decoder 경로 미확정 | 초기 지원 약속에서 제외 |

`charls`는 C++ CharLS와 연결되고, `openjpeg-sys`는 C OpenJPEG와 연결된다. `openjp2`는 Rust 포트이며 실제 대상 환경에서 검증해야 한다. 코어가 Rust여도 모든 codec 의존성이 순수 Rust인 것은 아니다. [라이브러리 지원 표](https://docs.rs/dicom-transfer-syntax-registry/0.10.0/dicom_transfer_syntax_registry/)

레지스트리에 UID가 등록되어 있는 것과 실행 가능한 decoder가 포함되어 있는 것을 구분한다. 위 feature 이름은 레지스트리 기준이며, 앱이 사용하는 상위 crate의 feature 전달과 최종 Cargo feature 집합을 확인한다. HTJ2K/JPEG XL의 앱 제외는 제품 범위 선택이며 라이브러리 전체의 미지원 선언이 아니다.

lossy 입력은 소실된 원본 값을 복원하지 못한다. 인코딩 특성과 기존 lossy compression 메타데이터를 유지해서 표시하고, 해당 디코딩 결과의 측정임을 기록한다. GDCM은 기본 의존성으로 넣지 않으며 필요한 자료를 다른 경로로 처리할 수 없을 때 검토한다.

## 파일 입력과 식별

- 기본 입력은 로컬 DICOM Part 10 파일과 이를 포함하는 디렉터리이다. 확장자는 판정 근거로 사용하지 않는다.
- DICOMDIR 해석은 후속 후보이다. v0.1은 디렉터리를 직접 탐색하므로 DICOMDIR에만 의존하지 않는다.
- file meta가 없는 raw dataset의 추정 파싱은 초기 지원 범위 밖이다. 잘못 추정해 읽은 결과를 정상 자료로 취급하지 않는다.
- Study/Series/SOP Instance UID를 기본으로 묶되, 동일 UID의 다른 파일 내용을 감지한다. 처음 발견한 파일로 조용히 덮어쓰지 않는다.
- UID 누락 파일은 앱 내부 식별자를 생성해 별도 목록에 둔다. 가짜 DICOM UID를 원본 값으로 저장하지 않는다.
- Specific Character Set에 따라 문자를 해석한다. UTF-8, 기본 문자셋과 실제 한글 자료를 시험하고, 해석 불가 시 태그 원문과 실패 상태를 구분한다. 임의의 시스템 인코딩으로 정상 환자명을 추정하지 않는다.
- private tag는 태그 패널에서 조회할 수 있지만 검증한 adapter가 없는 한 공간이나 정량 단위의 근거로 사용하지 않는다.

Part 10의 file meta SOP Class/Instance UID와 dataset의 대응 UID가 모두 있으면 일치 여부를 검사한다. 불일치 파일은 식별 충돌로 분리한다. 같은 SOP UID의 후보는 내용 해시가 같을 때만 중복 경로로 합치고, 비교 전에는 미확정 상태를 유지한다. 누락 UID에 부여한 내부 ID를 다른 source와의 자동 그룹화 근거로 사용하지 않는다.

## 픽셀 표현과 표시 파이프라인

v0.1의 기본 시험 대상은 8/16비트 정수 회색조와 지원 decoder가 해석한 컬러 프레임이다. Bits Allocated, Bits Stored, High Bit, Pixel Representation과 버퍼 길이가 일관되는지 확인한다. 1비트, Float Pixel Data, Double Float Pixel Data 및 32비트 정수 픽셀은 후속 후보로 명시한다.

회색조의 작업안은 저장 값 해석 → padding 식별 → Modality 변환 → VOI 선택 → IOD에 맞는 최종 극성 → 화면 출력 순서다. Rust는 표시 설명을 만들고 Metal은 이를 실행한다. Modality 변환이 적용된 버퍼인지 [API 계약](04-core-api-and-data-model.md)에 명시한다.

| 처리 | v0.1 규칙 |
| --- | --- |
| Signedness와 유효 비트 | 유효 비트를 기준으로 부호와 값을 해석하고 수치 시험으로 검증 |
| Modality 변환 | 선형 rescale 또는 지원 Modality LUT를 한 번 적용; 둘이 충돌하면 IOD 검증 결과에 따라 오류 처리 |
| VOI | LINEAR, LINEAR_EXACT, SIGMOID와 VOI LUT를 독립 시험; 구현하지 않은 필요한 변환은 지원 제한으로 표시 |
| 초기 VOI 선택 | 같은 원본에 유효한 저장 상태 → 유효한 파일 window 쌍의 첫 항목 → VOI LUT의 첫 항목 → 자동 범위 순서라는 앱 정책 제안 |
| 여러 VOI | 설명과 함께 선택 목록 제공; 서로 다른 window를 동시에 중복 적용하지 않음 |
| 자동 범위 | padding을 제외한 유효 값에서 계산; 균일 영상과 유효 값 없음은 별도 처리; 자동 설정임을 표시 |
| MONOCHROME1/2와 Presentation LUT | IOD별 규칙으로 극성을 한 번 결정; 단순한 중복 반전 방지 시험 포함 |
| 사용자 반전 | 해석된 기본 극성 위에 별도 표시 설정으로 적용 |
| Padding | 원본 값 영역에서 판정하고 마스크 유지; ROI와 자동 범위에서 제외 |
| 컬러 | RGB/YBR/Palette를 지원 조합별로 RGB 표시로 변환, 샘플링과 planar layout 시험 |

LINEAR의 폭 1은 임계값 동작이며 일반적인 선형 나눗셈과 구분해야 한다. VOI 함수별 정의역과 경계 조건을 따르고, 모든 함수에 동일한 폭 제한을 적용하지 않는다. [DICOM VOI LUT](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.11.2.html)

구체적으로 LINEAR는 width ≥ 1, LINEAR_EXACT와 SIGMOID는 width > 0을 요구한다. center/width는 유한한 값이어야 한다. Window Center/Width는 같은 개수의 쌍으로 해석한다. 지원하지 않는 VOI 함수나 필수 변환을 자동 window로 조용히 대체하지 않는다. VOI가 없는 경우의 표준상 identity와 앱의 자동 대비 선택은 구분하고, 후자는 사용자 표시 설정으로 기록한다.

자동 범위의 앱 정책은 유효 최솟값 a와 최댓값 b에 대해 a < b이면 LINEAR_EXACT(center=(a+b)/2, width=b-a), a=b이면 LINEAR_EXACT(center=a, width=1)이다. 균일 영상은 극성 적용 전 중간 밝기가 된다. 유효 픽셀이 없으면 자동 VOI를 만들지 않고 값 없음 상태를 표시한다. 파일의 필수 VOI가 누락된 경우에는 이 정책으로 정상 지원 상태를 부여하지 않는다.

Embedded Presentation LUT의 IDENTITY/INVERSE를 목표로 하고, 별도 Presentation State나 미지원 LUT Sequence가 있어야 완전한 표시가 가능한 자료는 제한을 명시한다. overlay와 shutter의 자동 적용은 초기 별도 지원 항목으로 남기며 미적용 사실을 확인할 수 있게 한다. 픽셀에 이미 포함된 문자와 그래픽은 영상의 일부로 표시한다.

DX Image Module은 slope=1, intercept=0인 identity 변환과 MONOCHROME2/IDENTITY 또는 MONOCHROME1/INVERSE 조합을 사용한다. MONOCHROME1과 INVERSE를 각각 반전시켜 상쇄하지 않는다. Pixel Intensity Relationship Sign을 추가 화면 반전의 근거로 사용하지 않는다. DX VOI LUT의 항목 비트 수는 10~16이라는 특수화가 있으므로 일반 VOI LUT의 8/16비트 검사만 재사용하지 않는다. [DICOM DX Image Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.11.3.html)

컬러 decoder의 실제 반환 색 표현과 채널 배치를 adapter에서 확인한다. 이미 RGB로 바뀐 출력에 원본 YBR 태그를 근거로 변환을 다시 적용하지 않는다. v0.1 기본 컬러 시험은 8비트 RGB, YBR_FULL/YBR_FULL_422 및 일반 Palette Color LUT로 한정한다. 고비트 RGB, segmented/enhanced palette와 추가 YBR 표현은 별도 검증 전 미지원으로 표시한다. [DICOM Image Pixel Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.3.html)

### 현재 SC 컬러 구현의 검증 범위 (2026-10-01)

COLOR-1은 비압축 단일 Secondary Capture의 unsigned8 RGB planar 0/1, YBR_FULL planar 0/1과 짝수 폭 YBR_FULL_422 planar 0을 처리한다. 422 입력 길이는 픽셀당 2 bytes이며 행별 `Y1,Y2,Cb,Cr`에서 RGBA를 만든다. 기존 공개 API와 revision 1은 유지한다. RGB는 그대로 전달하고 YBR은 Rust에서 한 번만 변환한다.

두 빌드의 [컬러 결과](implementation/results/P1-native-color.json)에서 독립 literal 7종, 예상 structured 거부 19종, FFI 복사·GPU 수명·확장 payload 예산을 확인했다. 실제 파일 선택 창과 최신 drawable 표시 회귀는 not-run이므로 앱 지원 완료로 판정하지 않는다. 합성 파일은 pixel module 시험 자료이며 완전한 IOD 적합성 증거가 아니다. US·Palette·고비트 컬러·odd-width 422·ICC·미구현 필수 컬러 변환과 압축/Enhanced/다중 프레임은 제외한다. US native Photometric에는 일반 Image Pixel Module 외에 US 전용 제약을 적용해야 한다. [DICOM US Image Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.5.6.html)

## 표시 종횡비와 물리 보정의 구분

화면의 픽셀 세로/가로 비율은 해당 프레임 전체에 적용되는 유효 Pixel Spacing, Imager Pixel Spacing, Nominal Scanned Pixel Spacing 순서로 찾는 앱 정책을 사용한다. 이들이 없으면 Pixel Aspect Ratio의 첫째/둘째 값을 사용한다. 모든 근거가 없으면 1:1로 표시하고 추정 상태를 남긴다. 잘못된 값이나 서로 다른 비율의 충돌은 진단에 남긴다. [DICOM Image Pixel Description Macro](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.3.3.html)

표시 비율을 아는 것과 환자 평면의 mm 간격을 아는 것은 별개다. Pixel Aspect Ratio만으로 mm/mm²를 계산하지 않는다. US의 개별 보정 영역을 전체 영상의 비율이나 물리 간격으로 확대 적용하지 않는다. 측정의 보정 상태는 아래 수치 규칙으로 별도 결정한다.

## 공간 좌표와 정렬

앱 내부 픽셀 좌표는 0부터 시작하는 픽셀 중심 좌표다. `i`는 열, `j`는 행이며 spacing 배열의 첫 값은 행 간격, 둘째 값은 열 간격이다. 사람의 환자 좌표는 LPS를 사용한다.

```text
P(i,j) = origin + i × column_spacing × row_direction
                + j × row_spacing × column_direction
normal = row_direction × column_direction
slice_position = dot(origin, reference_normal)
```

방향 벡터 이름은 DICOM Image Orientation Patient의 첫 세 값과 뒤 세 값에 대응한다. UI의 좌상단 원점과 환자 좌표를 혼동하지 않는다. [DICOM Image Plane Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.2.html)

LPS 방향 표시는 BIPED 또는 Anatomical Orientation Type이 없는 사람 자료를 기본 대상으로 한다. QUADRUPED를 사람의 방향 문자로 바꾸지 않고 초기에는 환자 방향 기능을 제한한다. origin과 방향 값의 유한성, 방향 벡터의 단위 길이·직교성, 유효 간격을 검사한다. 작은 반올림 오차만 기록된 허용오차 안에서 보정하며 퇴화 벡터로 공간 스택을 구성하지 않는다.

앱 정렬 정책은 다음과 같다.

1. 같은 시리즈 안에서도 Frame of Reference, orientation, 크기, spacing 및 시간/echo 등의 구분 가능한 차원을 검토해 display set을 나눈다.
2. 공간 정보가 충분한 각 set 안에서 기준 normal에 투영한 위치로 정렬한다. 파일명과 Instance Number는 공간 위치의 대체 근거가 아니다.
3. 동일 위치의 여러 프레임은 삭제하지 않는다. 구분 가능한 차원으로 분리하고, 모호하면 사용자에게 순서만 있는 목록으로 제공한다.
4. 위치나 방향이 없으면 결정적인 대체 순서로 열람은 허용할 수 있지만 환자 방향, 공간 연동과 MPR 자격은 부여하지 않는다. 대체 순서는 Instance Number, SOP UID, source ID 순으로 제안한다.
5. Slice Thickness를 슬라이스 중심 간격으로 사용하지 않는다. 간격과 누락 여부는 위치 차이에서 판단한다.

그룹화 허용오차의 초기 실험값은 방향 차이 0.1도, 간격 불규칙 판단은 `max(0.01 mm, 대표 간격의 1%)`로 제안한다. 이는 DICOM 표준값이 아니며, fixture와 실제 자료를 이용해 P0/P2에서 확정할 앱 정책이다. gantry tilt, 위치 이동, 불균일 간격이 있으면 단순한 정규 3D 볼륨으로 간주하지 않는다.

## Multi-frame과 시간

파일, 인스턴스와 프레임을 구분한다. 프레임 수가 2 이상이라는 사실만으로 cine 또는 볼륨을 판정하지 않는다. 초기 US cine는 SOP 의미와 Frame Increment Pointer 및 시간 태그를 해석해 시간축을 구성한다.

압축 Pixel Data의 fragment 하나를 프레임 하나로 간주하지 않는다. 채택한 전송 구문이 허용하는 다중 fragment 프레임, 비어 있는 Basic Offset Table과 Extended Offset Table을 검증한다. 경계를 확정할 수 없는 입력은 프레임을 임의로 나누지 않고 실패로 처리한다. [DICOM Encapsulated Pixel Data](https://dicom.nema.org/medical/dicom/current/output/chtml/part05/sect_A.4.html)

Frame Time Vector는 프레임 간 증가량이며 첫 항목은 0이다. 합산해 상대 시각을 만들고 배열 길이 및 값의 유효성을 확인한다. Frame Time, 권장 표시 속도와 Cine Rate는 같은 의미의 태그로 취급하지 않는다. [DICOM Cine Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.5.html)

앱은 기록된 시간축과 사용자가 선택한 재생 속도를 분리한다. Frame Increment Pointer가 가리키는 유효한 시간을 우선 사용한다. 사용할 수 없으면 유효한 권장 표시 속도, Cine Rate, 사용자 기본 속도의 순서로 대체하는 작업안을 사용하고 `timing_source`에 근거를 남긴다. 추정 재생을 실제 획득 시각으로 표시하지 않는다.

UI의 재생 경과 시간은 첫 표시 프레임을 0 ms로 둔다. Frame Delay는 별도로 보존하며 이 경과 시간에 더하지 않는다. 획득 기준 상대 시각을 제공할 때는 표준 시간식과 기준점을 명시한다. 가변 간격은 원본 배열을 보존한다. 다중 프레임에서 재생 간격이 0 이하이거나 비유한 값이면 기본 순차 재생용 시간축을 대체하고 제한 사유를 표시한다. 이 경우 대체 시각을 획득 시각으로 저장하지 않는다.

반복 재생 마지막 프레임의 유지 시간은 명시 정보가 없을 때 선택 구간의 양의 프레임 간격 중앙값으로 제안하며 추정값으로 표시한다. 한 프레임에는 재생 기능을 활성화하지 않는다.

v0.1 작업안은 유효한 Start/Stop Trim의 양 끝 프레임을 포함해 초기 재생 범위로 사용하며, 누락 끝점은 각각 1/N으로 둔다. 범위 밖이거나 start > stop이면 전체 범위로 대체하고 이유를 표시한다. 원본 프레임 수와 저장 참조 번호는 trim으로 변경하지 않는다. Preferred Playback Sequencing이 유효하면 loop/sweep의 초기값으로 사용하고 없으면 loop를 사용한다. sweep은 끝 프레임을 중복하지 않으며 가변 시간의 역방향 구간은 같은 두 프레임 사이의 간격을 사용한다. 사용자는 전체 범위와 재생 방식을 바꿀 수 있다.

Enhanced CT/MR에서는 Shared/Per-frame Functional Groups와 Dimension Index를 처리해야 한다. 같은 Functional Group이 shared와 per-frame에 중복되는 잘못된 입력을 임의의 우선순위로 덮지 않는다. 현재 단계에서 해석하지 못하면 일반 CT/MR 스택으로 자동 변환하지 않는다. [Functional Groups](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.16.html), [Multi-frame Dimension](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.17.html)

## 수치와 측정

CT는 적용 가능한 변환과 단위를 확인한 경우 HU를 표시한다. MR/US/SC에 modality 이름만으로 HU를 부여하지 않는다. 정량 MR과 Real World Value Mapping은 해당 매핑을 지원하고 검증하기 전에는 보정된 물리값이라고 표현하지 않는다.

거리와 면적에는 다음 보정 상태를 함께 저장한다.

| 상태 | 표시 정책 |
| --- | --- |
| PatientPlane | CT/MR의 유효한 환자 평면 픽셀 간격에 따른 mm와 mm²; origin/orientation이 없어도 2D 측정은 가능하나 LPS와 공간 연동은 불가 |
| CalibratedProjection | 보정 근거가 있는 X-ray의 mm와 보정 설명 |
| ProjectionUnverified | Pixel Spacing은 있지만 보정 여부 불명; 수치에 보정 미확인 표시 |
| DetectorPlane | 검출기 간격만 있는 경우 검출기 기준 mm라고 명시 |
| ScannedPlane | Nominal Scanned Pixel Spacing만 있으면 스캔 매체 기준 mm로 명시하며 환자 평면과 구분 |
| UltrasoundRegion | 검증된 US 영역의 축 단위와 보정 범위 사용; 후속 기능 |
| PixelOnly | 물리 간격 없음; px와 px² 사용 |

X-ray의 Pixel Spacing이 있다고 항상 확대 보정이 확인된 것은 아니다. Imager Pixel Spacing, Nominal Scanned Pixel Spacing 및 Calibration Type/Description을 함께 검토한다. [DICOM Basic Pixel Spacing Calibration](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_10.7.html)

보정 판정의 작업안은 유효한 Calibration Type 또는 검출기·스캔 간격과 다른 Pixel Spacing을 보정 근거로 기록하는 것이다. Calibration Type이 없고 간격이 같은 경우는 해당 검출기·스캔 평면 기준으로 표시한다. Pixel Spacing만 있고 비교 근거가 없으면 ProjectionUnverified로 둔다. 양의 유효 간격이 없으면 PixelOnly로 제한한다. 보정된 투영 영상도 보정 물체·깊이의 적용 범위를 벗어난 모든 구조의 실제 길이를 보장하지 않는다.

US는 영역마다 물리 단위와 배율이 다를 수 있다. US 물리 측정을 추가할 때는 양 끝점과 경로가 유효한 보정 영역에 있는지, 양 축이 거리 단위인지 확인한다. Doppler의 시간·속도 축에 일반 거리 측정을 적용하지 않는다. v0.1은 픽셀 측정과 주석까지만 기본 제공한다. [DICOM US Region Calibration](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.5.5.html)

ROI 통계는 원본 픽셀 중심으로 포함 여부를 판정하고, padding과 무효 값을 제외한 Modality 변환 후 값에서 계산한다. 화면 보간 값과 window/level 결과를 사용하지 않는다. 평균, 모집단 표준편차, 최솟값, 최댓값, 유효 개수, 제외 개수와 단위를 저장한다. 유효 값이 없으면 결과 없음, 하나면 표준편차 0으로 정의한다. 컬러 ROI 수치와 서로 다른 물리 단위가 섞인 ROI는 초기 지원 범위 밖이다.

## 지원 명세를 갱신하는 기준

새 조합을 지원으로 바꾸려면 decoder 성공 외에 표시, 프레임 순서, 필요한 변환, 오류 처리를 검증해야 한다. 측정 지원은 별도 결과로 기록한다. 시험 자료의 출처, 사용 조건, 해시, 기대 결과와 실행 버전을 [검증 계획](06-development-and-validation.md)에 맞춰 연결한다.

관련 구현 계약은 [코어 API와 데이터 모델](04-core-api-and-data-model.md)을 따른다. 수학적 경계 조건을 포함한 시험 목록은 T-03부터 T-10 및 T-21에 정의한다. 표준 근거는 검토 시 조회한 DICOM PS3.3/PS3.5 2026d의 해당 절이며, 앱 정책으로 표시한 우선순위·허용오차·기본값은 표준의 의무값과 구분한다.
