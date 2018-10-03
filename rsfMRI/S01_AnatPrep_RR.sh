# ===============================================================   
# Date: 11/12/2015
# Authors: Javier Gonzalez-Castillo
#
# Inputs:
#   * SubjectID is the only input parameter
#
# Outputs:
#   * Skull-strip PD
#   * Intracranial mask based on PD
#   * Create Skull Stripped and Bias Corrected MP-RAGE
#   * Perform trasformation to MNI space
#
# ===============================================================   

# COMMON STUFF
# ============
source ./00_CommonVariables.sh
set -e
minp=11      # Minimum patch size as recommended by BOB for the NL Alignment
usePD4mask=0 # Use PD for computing intra-cranial mask (helps keep the TLs)

# READ INPUT PARAMETERS
# =====================
# INPUT VARIABLES REQUIRED
# ========================
if [[ -z "${SBJ}" ]]; then
        echo "You need to provide SBJ as an environment variable"
        exit
fi
### if [ $# -ne 1 ]; then
###  echo "Usage: $basename $0 SBJID"
###  exit
### fi
### SBJ=$1


# CREATE DIRECTORIES AND COPY FILES
# =================================
cd ${PRJDIR}/PrcsData/${SBJ}
echo -e "\033[0;33m++ INFO: Creating D01_Anatomical Directory and linking necessary files.\033[0m"
if [ ! -d D01_Anatomical ]; then mkdir D01_Anatomical; fi
cd D01_Anatomical
ln -fvs ${PRJDIR}/Scripts/MNI152_T1_2009c_uni+tlrc.* .
ln -fvs ../D00_OriginalData/${SBJ}_t1_memprage*.nii.gz .

# COMBINE THE DIFFERNET ECHOES
# ============================
echo -e "\033[0;33m++ INFO: Averaging all ME-MEMPRAGE datasets into $SBJ_Anat+orig.\033[0m"
3dMean -overwrite -prefix ${SBJ}_Anat ${SBJ}_t1_memprage.nii.gz
# CREATE INTRACRANIAL MASK
# ========================
echo -e "\033[0;33m++ INFO: Intensity Bias Correction for Anatomical scan.\033[0m"
3dUnifize -overwrite -prefix ${SBJ}_Anat_bc -input ${SBJ}_Anat+orig. -GM -ssave ${SBJ}_Anat.UN.Bias

if [ "${noisyANAT}" -eq "1" ]; then
   if [ "${usePD4mask}" -eq "1" ]; then
     echo -e "\033[0;33m++ INFO: Skull-stripping via noisy appraoach [BASED ON PD]\033[0m"
     @NoisySkullStrip -input ${SBJ}_Anat_PD_bc+orig 
     3dcalc -a ${SBJ}_Anat_PD_bc.ns+orig -expr 'step(a)' -overwrite -prefix ${SBJ}_Anat_mask
     rm ${SBJ}_Anat_PD_bc.ns+orig.*
     rm ${SBJ}_Anat_PD_bc.skl+orig.*
     rm ${SBJ}_Anat_PD_bc.nsm+orig.*
     rm ${SBJ}_Anat_PD_bc.ma+orig.*
     rm ${SBJ}_Anat_PD_bc.lsp+orig.*
     rm ${SBJ}_Anat_PD_bc.ls+orig.* 
     rm ${SBJ}_Anat_PD_bc.air+orig.*
     rm __MA_h.1D
     rm __MA_hd.1D
   else 
     echo -e "\033[0;33m++ INFO: Skull-stripping via noisy appraoach [BASED ON MPRAGE]\033[0m"
     @NoisySkullStrip -input ${SBJ}_Anat_bc+orig 
     3dcalc -a ${SBJ}_Anat_bc.ns+orig -expr 'step(a)' -overwrite -prefix ${SBJ}_Anat_mask
     rm ${SBJ}_Anat_bc.ns+orig.*
     rm ${SBJ}_Anat_bc.skl+orig.*
     rm ${SBJ}_Anat_bc.nsm+orig.*
     rm ${SBJ}_Anat_bc.ma+orig.*
     rm ${SBJ}_Anat_bc.lsp+orig.*
     rm ${SBJ}_Anat_bc.ls+orig.* 
     rm ${SBJ}_Anat_bc.air+orig.*
     rm __MA_h.1D
   fi
else
   echo -e "\033[0;32m++ INFO: Skull-stripping via regular approach \033[0m"
   3dSkullStrip -prefix ${SBJ}_Anat_mask -ld 33 -niter 777 -shrink_fac_bot_lim 0.777 -exp_frac 0.0666 -input ${SBJ}_Anat_bc+orig
   3dcalc -a ${SBJ}_Anat_mask+orig. -expr 'step(a)' -overwrite -prefix ${SBJ}_Anat_mask
fi

###echo -e "\033[0;33m++ MANUAL INTERVENTION NEEDED: Check that the mask is ok, and correct when necessary [${SBJ}_Anat_mask] \033[0m"
###read -n1 -rsp $'Press ENTER to continue:'
3dcalc -overwrite -a ${SBJ}_Anat_bc+orig -m ${SBJ}_Anat_mask+orig -expr 'a*m' -prefix ${SBJ}_Anat_bc_ns
# CONVERT ANATOMICAL TO MNI SPACE
# ===============================
if [ "${doNL}" -eq "1" ]; then
  echo -e "\033[0;33m++ INFO: Alignment to MNI space will be via non-linear registration \033[0m"
  3dQwarp -overwrite \
          -allineate \
          -blur -3 -3  -iwarp -duplo \
          -workhard:0:4 \
          -noneg \
          -pblur \
          -minpatch ${minp} \
          -base MNI152_T1_2009c_uni+tlrc \
          -source ${SBJ}_Anat_bc_ns+orig \
          -prefix ${SBJ}_Anat_bc_ns

else
  echo -e "\033[0;33m++ INFO: Alignment to MNI space will be via linear registration \033[0m"
  @auto_tlrc -overwrite -base MNI152_T1_2009c_uni+tlrc -input ${SBJ}_Anat_bc_ns+orig. -no_ss -twopass
  cat_matvec -ONELINE ${SBJ}_Anat_bc_ns+tlrc::WARP_DATA > ${SBJ}_MNI2Anat.Xaff12.1D
  cat_matvec -ONELINE ${SBJ}_MNI2Anat.Xaff12.1D -I      > ${SBJ}_Anat2MNI.Xaff12.1D
  rm ${SBJ}_Anat_bc_ns_WarpDrive.log
  rm ${SBJ}_Anat_bc_ns.Xaff12.1D
  rm ${SBJ}_Anat_bc_ns.Xat.1D
fi

# Create Autobox version for visualization
# ========================================
3dAutobox -overwrite -input ${SBJ}_Anat_bc_ns+tlrc -prefix  ${SBJ}_Anat_bc_ns.AB

# GZIP All files
# ==============
gzip ${SBJ}_Anat*BRIK
echo -e "\033[0;32m++ INFO: =================================================  \033[0m"
echo -e "\033[0;32m++ INFO: =========  SCRIPTS FINISHED SUCCESSFULY    ======  \033[0m"
echo -e "\033[0;32m++ INFO: =================================================  \033[0m"


