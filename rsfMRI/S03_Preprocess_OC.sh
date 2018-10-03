# ============================================================================
# Author: Javier Gonzalez-Castillo
# Date:   November/12/2017
#
# Purpose:
#    Run the OC pipeline
# Usage:
#    export SBJ=SBJ01 RUN=Event01; sh ./S04_Preprocess_OC.sh
#  
# ============================================================================
Numjobs=6
# Check for input parameters
# ==========================
if [[ -z "${SBJ}" ]]; then
        echo "You need to provide SBJ as an environment variable"
        exit
fi
if [[ -z "${RUN}" ]]; then
        echo "You need to provide RUN as an environment variable"
        exit
fi
set -e

# Common Stuff
# ============
source ./00_CommonVariables.sh
MASK_FB_MNI=`echo ${SBJ}_${RUN}.REF.mask.FBrain.MNI.nii.gz`
# Enter the D02_Preprocessed directory
# ===============================
cd ${PRJDIR}/PrcsData/${SBJ}

if [ ! -d D02_Preprocessed ]; then
        echo "Pre-processing directory does not exits."
        exit
fi

cd D02_Preprocessed

# Load all necessary info: Number of echoes, echo files, etc...
# =============================================================
Ne=`ls ../D00_OriginalData/${SBJ}_${RUN}_E??.nii.gz | wc -l | awk '{print $1}'`
echo -e "\033[0;32m++ INFO: Number of Echoes=${Ne}\033[0m"
DataFiles=()
for i in `seq 1 $Ne`
do
   EchoID=`printf %02d $i`
   File=`echo ${SBJ}_${RUN}_E${EchoID}.nii.gz`
   DataFiles[$i]=${File}
   Prefix=`echo ${SBJ}_${RUN}_E${EchoID}`
   DataPrefixes[$i]=${Prefix}
done
echo -e "\033[0;32m++ INFO: Working Directory:\033[0m" `pwd`

# Axialize for proper memory allocation in Phyton
# ===============================================
echo -e "\n"
echo -e "\033[0;32m++ STEP (1) Axialize files prior to Z-cat\033[0m"
echo -e "\033[0;32m=========================================\033[0m"
for i in `seq 1 $Ne`
do
    3daxialize -overwrite -prefix pc03.${DataPrefixes[$i]}.volreg.nii.gz pc03.${DataPrefixes[$i]}.volreg.nii.gz
done
3daxialize -overwrite -prefix ${MASK_FB_MNI} ${MASK_FB_MNI}

# Concatenate EPI datasets in Z-direction# =======================================
echo -e "\n"
echo -e "\033[0;32m++ STEP (2) Z-concatenating echo files\033[0m"
echo -e "\033[0;32m======================================\033[0m"
FilesToZcat=`ls pc03.${SBJ}_${RUN}_E??.volreg.nii.gz | tr -s '\n' ' '`
echo -e "\033[0;32m++ Files concatenated in Z-direction: ${FilesToZcat}\033[0m" 
3dZcat -overwrite -prefix pc06.${SBJ}_${RUN}.zcat.data.nii.gz ${FilesToZcat}

# Concatenate EPI intra-cranial mask in Z-direction
# =================================================
echo -e "\n"
echo -e "\033[0;32m++ STEP (3) Z-concatenating mask files\033[0m"
echo -e "\033[0;32m======================================\033[0m"
MasksToZcat='';for i in `seq 1 $Ne`; do MasksToZcat=`echo "${MasksToZcat} ${MASK_FB_MNI}"`; done
echo -e "\033[0;32m++ Files concatenated in Z-direction: ${MasksToZcat}\033[0m"
3dZcat -overwrite -prefix pc06.${SBJ}_${RUN}.zcat.mask.nii.gz ${MasksToZcat}

# Mask the EPI Z-concatenated file (input to ME-ICA)
# ==================================================
echo -e "\n"
echo -e "\033[0;32m++ STEP (4) Masking the Z-cat file\033[0m"
echo -e "\033[0;32m==================================\033[0m"
3dcalc -float -overwrite -m pc06.${SBJ}_${RUN}.zcat.mask.nii.gz \
                         -d pc06.${SBJ}_${RUN}.zcat.data.nii.gz \
        -expr 'm*d' -prefix pc06.${SBJ}_${RUN}.zcat.data.nii.gz 


# Compute the t2s maps
# ====================
echo -e "\n"
echo -e "\033[0;32m++ STEP (5) Compute Static T2s and S0 Maps\033[0m"
echo -e "\033[0;32m==========================================\033[0m"
module load python/3.6
# module load Anaconda
# source activate /data/RS_preprocess/Apps/envs/inati_meica_p27
python /data/Epilepsy_EEG/Apps/SFIM_ME/rt_tools/me_get_staticT2star.py \
       -d     pc06.${SBJ}_${RUN}.zcat.data.nii.gz           \
       --mask ${MASK_FB_MNI}                                  \
       --tes_file ${SBJ}_${RUN}_Echoes.1D                   \
       --out_dir  ./                                          \
       --prefix   pc07.${SBJ}_${RUN}                        \
       --ncpus ${Numjobs}

3drefit -space MNI pc07.${SBJ}_${RUN}.sTE.t2s.nii 
3drefit -space MNI pc07.${SBJ}_${RUN}.sTE.S0.nii 
3drefit -space MNI pc07.${SBJ}_${RUN}.sTE.mask.nii 
3drefit -space MNI pc07.${SBJ}_${RUN}.SME.nii 

# Compute Optimally Combined 
# ==========================
echo -e "\n"
echo -e "\033[0;32m++ STEP (6) Compute Optimally Combined TS\033[0m"
echo -e "\033[0;32m=========================================\033[0m"
python /data/Epilepsy_EEG/Apps/SFIM_ME/rt_tools/me_get_OCtimeseries.py \
           -d pc06.${SBJ}_${RUN}.zcat.data.nii.gz           \
       --mask ${MASK_FB_MNI}                                  \
       --t2s pc07.${SBJ}_${RUN}.sTE.t2s.nii            \
       --tes_file ${SBJ}_${RUN}_Echoes.1D                   \
       --out_dir  ./                                          \
       --prefix   pc07.${SBJ}_${RUN}                        

# source deactivate /data/RS_preprocess/Apps/envs/inati_meica_p27
# Correct space to MNI
# ====================
if [ -f pc07.${SBJ}_${RUN}.OCTS.nii ]; then gzip -f pc07.${SBJ}_${RUN}.OCTS.nii; fi
3drefit -space MNI pc07.${SBJ}_${RUN}.OCTS.nii.gz

# Create Ventricular Regressor for OC
# ===================================
MASK_CSF_ORIG=`echo ${SBJ}_${RUN}.REF.mask.CSF.nii.gz`
MASK_CSF_MNI=`echo  ${SBJ}_${RUN}.REF.mask.CSF.MNI.nii.gz`
MNI_MASTER_TEMPLATE=`echo ${PRJDIR}/Scripts/MNI152_T1_2009c_uni.LR2iso+tlrc`
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Create Physio Regressor <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dNwarpApply -overwrite -ainterp NN                                                                                                                                                \
                  -source ${MASK_CSF_ORIG}                                                                                                                                         \
                  -nwarp ''''../D01_Anatomical/${SBJ}'''_Anat_bc_ns_WARP+tlrc '''${SBJ}'''_'''${RUN}'''.REF2Anat.Xaff12.1D '''${SBJ}'''_'''${RUN}'''_matrix_intrarun.aff12.1D '''${SBJ}'''_'''${RUN}'''_E01.blip_warp_For_WARP+orig' \
                  -master ${MNI_MASTER_TEMPLATE}                                                                                                                                   \
                  -prefix ${MASK_CSF_MNI}
3dpc -overwrite -dmean -pcsave 5 -mask ${MASK_CSF_MNI} -prefix ${SBJ}_${RUN}_OCTS.CSF.PCA pc07.${SBJ}_${RUN}.OCTS.nii.gz
rm ${SBJ}_${RUN}_OCTS.CSF.PCA??.1D
rm ${SBJ}_${RUN}_OCTS.CSF.PCA_eig.1D
rm ${SBJ}_${RUN}_OCTS.CSF.PCA+tlrc.*

# Remove regressors of no interest
# ================================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Remove Nuisance Signals <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dTproject -overwrite                                           \
               -mask ${MASK_FB_MNI}                             \
               -input  pc07.${SBJ}_${RUN}.OCTS.nii.gz         \
               -prefix pc08.${SBJ}_${RUN}_OCTS.project.nii.gz \
               -blur 6                                          \
               -polort 5                                        \
               -ort ${SBJ}_${RUN}_Motion.demean.1D            \
               -ort ${SBJ}_${RUN}_Motion.demean.der.1D        \
               -ort ${SBJ}_${RUN}_OCTS.CSF.PCA_vec.1D

# Compute spc for OC
# ==================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Convert to SPC <---------------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dBlurInMask -overwrite -FWHM 6                                 \
             -mask        ${MASK_FB_MNI}                        \
             -input  pc07.${SBJ}_${RUN}.OCTS.nii.gz           \
             -prefix pc08.${SBJ}_${RUN}_OCTS.blur.nii.gz
3dTstat -overwrite -mean                                        \
              -prefix pc08.${SBJ}_${RUN}_OCTS.MEAN.nii.gz     \
                      pc08.${SBJ}_${RUN}_OCTS.blur.nii.gz
3dcalc  -overwrite -a pc08.${SBJ}_${RUN}_OCTS.project.nii.gz  \
                   -m pc08.${SBJ}_${RUN}_OCTS.MEAN.nii.gz     \
                   -expr 'a/m'                                  \
                   -prefix pc09.${SBJ}_${RUN}_OCTS.spc.nii.gz

echo -e "\n"
echo -e "\033[0;32m#====================================#\033[0m"
echo -e "\033[0;32m#  SUCCESSFUL TERMINATION OF SCRIPT  #\033[0m"
echo -e "\033[0;32m#====================================#\033[0m"

