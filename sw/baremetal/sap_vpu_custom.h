#ifndef SAP_VPU_CUSTOM_H
#define SAP_VPU_CUSTOM_H

#include <stdint.h>

#define SAP_OPCODE_CUSTOM0 0x0b

#define SAP_FUNCT7_VSET 0x09
#define SAP_FUNCT7_VMOV 0x09
#define SAP_FUNCT7_VDOT 0x10
#define SAP_FUNCT7_VSETPREC 0x18
#define SAP_FUNCT7_VREADCNT 0x1a
#define SAP_FUNCT7_VSETLANE 0x1b
#define SAP_FUNCT7_VSETSPARSE_BMP 0x1c
#define SAP_FUNCT7_VCLEARCNT 0x1d

#define SAP_FUNCT3_VSET 0x0
#define SAP_FUNCT3_VMOV 0x1

#define SAP_PREC_INT8 0x0
#define SAP_PREC_INT4 0x1
#define SAP_PREC_INT2 0x2

#define SAP_CNT_CYCLE 0x0
#define SAP_CNT_INST 0x1
#define SAP_CNT_MAC_ACTIVE 0x2
#define SAP_CNT_SKIPPED 0x3
#define SAP_CNT_SPARSE 0x4
#define SAP_CNT_LANE 0x5

#define SAP_R_TYPE(funct7, funct3, rd, rs1, rs2) \
  ((((uint32_t)(funct7) & 0x7fu) << 25) | \
   (((uint32_t)(rs2) & 0x1fu) << 20) | \
   (((uint32_t)(rs1) & 0x1fu) << 15) | \
   (((uint32_t)(funct3) & 0x7u) << 12) | \
   (((uint32_t)(rd) & 0x1fu) << 7) | \
   ((uint32_t)SAP_OPCODE_CUSTOM0))

#define SAP_ENC_VSET(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VSET, SAP_FUNCT3_VSET, rd, rs1, rs2)
#define SAP_ENC_VMOV(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VMOV, SAP_FUNCT3_VMOV, rd, rs1, rs2)
#define SAP_ENC_VDOT(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VDOT, 0, rd, rs1, rs2)
#define SAP_ENC_VSETPREC(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VSETPREC, 0, rd, rs1, rs2)
#define SAP_ENC_VREADCNT(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VREADCNT, 0, rd, rs1, rs2)
#define SAP_ENC_VSETLANE(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VSETLANE, 0, rd, rs1, rs2)
#define SAP_ENC_VSETSPARSE_BMP(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VSETSPARSE_BMP, 0, rd, rs1, rs2)
#define SAP_ENC_VCLEARCNT(rd, rs1, rs2) SAP_R_TYPE(SAP_FUNCT7_VCLEARCNT, 0, rd, rs1, rs2)

#endif
