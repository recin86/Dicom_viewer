# P0-DATA-CLOSE 자료 준비

공개 331개와 동결된 CODEC manifest 381개를 읽기 전용으로 연결하고, 부족한 정상 CT·DX·US 합성 자료를 만든다. 생성 DICOM과 golden은 `~/Library/Caches/dicom-viewer/p0-data/`에만 두며 저장소에는 스크립트와 식별 정보 없는 JSON을 보관한다. task 기준은 `ea7e2b3`와 현재 CODEC 실험 상태다.

```bash
~/Library/Caches/dicom-viewer/p0-codec/venv/bin/python experiments/p0-data/prepare.py
```

Python 3.12.13·pydicom 3.0.2의 CODEC 격리 환경을 사용한다. 옵션 `--work-dir`, `--codec-report`, `--inventory`, `--local-data`, `--report`로 입력을 지정할 수 있다. 생성 경로가 저장소 안이면 실행을 거부한다. 같은 입력과 도구 버전에서 생성 bytes는 결정적이다. 원본 파일을 고치거나 복사하지 않는다.

| 합성 자료 | 독립 기대값 | 준비 검증 |
| --- | --- | --- |
| CT 32개, 512×512 | signed16 저장 값 공식, slope1.5/intercept−1024, LPS origin과 0.7/0.4/1.5mm 간격, geometry 순서 | 전체 픽셀과 geometry/rescale 태그 readback; 파일명과 역순 InstanceNumber를 정렬 근거로 쓰면 기대 순서와 다름 |
| DX 3개, 16×16 | unsigned12, identity rescale, MONO2/IDENTITY·MONO1/INVERSE, calibrated/detector/unverified 간격과 단위 근거 | 전체 픽셀과 극성·보정 태그 readback; 화면 극성/거리 결과의 제품 시험은 미실행 |
| US 3개, 640×480 | RLE grayscale; fixed40ms 300프레임, vector[0,40,60]ms 3프레임, 시간 없음 3프레임 | 전체 306프레임 픽셀·BOT·시간 태그 readback; 원본 0기반 index/1기반 번호, trim2..3의 경과[0,60]ms를 golden에 보존 |

CT와 US는 명시한 정수 공식으로 픽셀을 만든다. 좌표·시간·보정 golden은 제품 함수를 사용하지 않는다. US의 시간 없는 사례에서 user-default30fps는 시험용 재생 정책이며 획득 시각이 아니다. Frame Delay17ms는 UI 경과 시간에 더하지 않는다. DX는 [DX Image Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.11.3.html)의 unsigned representation·identity rescale·극성 조합을 보존한다. 좌표와 cine 근거는 [Image Plane Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.2.html), [Cine Module](https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.7.6.5.html)에 연결된다.

`results/preparation.json`은 기존 자료의 SOP/Transfer Syntax/Modality/Enhanced 분포, 출처·조건·content SHA, 새 fixture manifest·golden, readback 결과와 gap plan을 담는다. 환자 정보·원본 경로·파일명·Instance UID는 기록하지 않는다. 공개 파일의 중복 해시는 별도로 세며 수집 자료의 파일 비중을 임상 사용 빈도로 해석하지 않는다.

실행의 exit0은 **fixture 준비 pass**다. 제품 T-03~09, 실제 표시·cine·측정, 완전한 IOD 적합성과 제조사 호환성 시험은 `not-run`이다. 합성 RLE의 같은 encoder/decoder readback은 외부 코덱 호환성 근거가 아니다. CODEC의 fail/not-run을 이 준비 결과로 합격으로 바꾸지 않는다.

P2/P5 전에 제조사의 tilt 없는 일반 CT 시리즈, DX의 보정 출처와 실제 detector 처리, 긴 US cine의 고정/가변 획득 시간을 확보해야 한다. MR echo/time·Frame of Reference 경계, DX VOI LUT10~16bit와 signed 입력 거부, US의 다른 축 단위를 가진 보정 영역, 누락/충돌 UID·깊은 sequence·파일 복구·표시 비율 경계도 [제품 시험 계획](../../docs/06-development-and-validation.md)에 따라 준비해야 한다. Enhanced CT/MR은 현재 후보 범위이며 Functional Groups와 Dimension Index 해석을 이 스크립트가 구현하지 않는다.

## 실행 결과 (2026-09-30)

- 인수 후 수정: 단일 값 AT 태그(Frame Increment Pointer)를 pydicom이 리스트가 아닌 단일 tag로 돌려줘 US readback이 `TypeError`로 중단되던 버그를 `at_values()`로 고쳤다. CT golden의 모호한 키 `pixel_2_3_lps_mm`를 `pixel_row3_col2_lps_mm`로 바꿨다(값 동일: row 3·col 2 → [10.8, 22.1, z]).
- 대상 Mac(Apple M5, macOS 27.0, CODEC venv Python 3.12.13·pydicom 3.0.2·numpy 2.5.3): **exit 0, fixture 준비 pass.** 합성 38개(CT 32·DX 3·US 3), 341 프레임, 102,392,576 픽셀 전부 readback 일치, 공개 331개 원본 해시와 CODEC 보고서·목록 해시 불변. 결과 [preparation.json](results/preparation.json). P0 독립 검토(F11)에 따라 DX unverified·US missing-time의 condition에 의도적 비적합(Type 1 속성 생략)을 표시하고, CT 정렬 방향 주석과 부족 자료 두 항목(PixelSpacing=ImagerPixelSpacing DetectorPlane 규칙, 640×480 컬러 300프레임 성능 사례)을 추가해 Mac에서 재실행했다(13:03 UTC, 스크립트 SHA-256 `b67448c5…fb4a`). 합성 DICOM 38개의 해시는 수정 전과 같다.
- 사전 검증: Cowork Linux VM(aarch64, 같은 Python·pydicom·numpy 버전)에서 두 번 실행한 합성 파일 해시가 서로 같고, Mac 실행 해시와도 38개 모두 같았다. 생성 결과는 플랫폼 간 결정적이다.
- golden 독립 대조(Claude 인수 시 수작업): CT LPS 좌표(열 방향 0.4 mm·행 방향 0.7 mm), 파일명 순서의 역원(13⁻¹ ≡ 5 mod 32), DX MONO1/INVERSE 극성과 보정 상태별 간격, US FrameTimeVector 누적 [0,40,100] ms와 trim 2..3 경과 [0,60] ms를 확인했다.
- 제품 T-03~T-09, 제조사 호환성, 완전한 IOD 적합성은 not-run이다. 위 "P2/P5 전에" 부족 자료는 그대로 남는다.
