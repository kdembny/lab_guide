# ============================================================================
# Author: Javier Gonzalez-Castillo
# Date:   November/12/2017
#
# Purpose:
#    Run MEICA, remove physio, compute SPC time series
# Usage:
#    export SBJ=SBJ01 RUN=Event01; sh ./S04_Preprocess_MEICA.sh
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
MASK_CSF_MNI=`echo ${SBJ}_${RUN}.REF.mask.CSF.MNI.nii.gz`
# Enter the D02_Preprocessed directory
# ===============================
cd ${PRJDIR}/PrcsData/${SBJ}

if [ ! -d D02_Preprocessed ]; then
        echo "Pre-processing directory does not exits."
        exit
fi

cd D02_Preprocessed

# RUN TE-DEPENDENCE DENOISING
# ===========================
module load python/2.7
# module load Anaconda
# source activate /data/RS_preprocess/Apps/envs/inati_meica_p27
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Run MEICA Denoising <----------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
ECHOTIMES=`cat ${SBJ}_${RUN}_Echoes.1D`
echo ${ECHOTIMES}
MEICADIR=`echo MEICA_KDAW12_${RUN}`
#python /data/Epilepsy_EEG/Apps/me-ica/meica.libs/tedana.py \
python /data/Epilepsy_EEG/Apps/MEICA3/me-ica/meica.libs/tedana.py \
                      -d pc06.${SBJ}_${RUN}.zcat.data.nii.gz  \
                      -e ${ECHOTIMES}                           \
                      --label=${MEICADIR}
                      #--kdaw=12 --label=${MEICADIR}
3dcopy -overwrite TED.${MEICADIR}/dn_ts_OC.nii pc07.${SBJ}_${RUN}.MEICA.nii.gz
3drefit -space MNI pc07.${SBJ}_${RUN}.MEICA.nii.gz

echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Create MEICA Report <----------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
python /data/Epilepsy_EEG/Apps/Meica_Report/meica_report.py              \
       -t ${PRJDIR}/PrcsData/${SBJ}/D02_Preprocessed/TED.${MEICADIR}/        \
       -o ${PRJDIR}/PrcsData/${SBJ}/D02_Preprocessed/TED.${MEICADIR}/Report/ \
 --motion ${PRJDIR}/PrcsData/${SBJ}/D02_Preprocessed/${SBJ}_${RUN}_Motion.1D  \
 --ncpus 1 --overwrite 
# source deactivate /data/RS_preprocess/Apps/envs/inati_meica_p27

echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Create Physio Regressor <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dpc -overwrite -dmean -pcsave 5 -mask ${MASK_CSF_MNI} -prefix ${SBJ}_${RUN}_MEICA.CSF.PCA pc07.${SBJ}_${RUN}.MEICA.nii.gz
rm ${SBJ}_${RUN}_MEICA.CSF.PCA??.1D
rm ${SBJ}_${RUN}_MEICA.CSF.PCA_eig.1D
rm ${SBJ}_${RUN}_MEICA.CSF.PCA+tlrc.*

# Remove regressors of no interest
# ================================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Remove Nuisance Signals <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dTproject -overwrite                                            \
               -mask ${MASK_FB_MNI}                              \
               -input  pc07.${SBJ}_${RUN}.MEICA.nii.gz         \
               -prefix pc08.${SBJ}_${RUN}_MEICA.project.nii.gz \
               -blur 6                                           \
               -polort 5                                         \
               -ort ${SBJ}_${RUN}_Motion.demean.1D             \
               -ort ${SBJ}_${RUN}_Motion.demean.der.1D         \
               -ort ${SBJ}_${RUN}_MEICA.CSF.PCA_vec.1D

# Compute spc for MEICA
# =====================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Convert to SPC <---------------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dBlurInMask -overwrite -FWHM 6 \
             -mask        ${MASK_FB_MNI} \
             -input  pc07.${SBJ}_${RUN}.MEICA.nii.gz \
             -prefix pc08.${SBJ}_${RUN}_MEICA.blur.nii.gz
3dTstat -overwrite -mean \
              -prefix pc08.${SBJ}_${RUN}_MEICA.MEAN.nii.gz \
                      pc08.${SBJ}_${RUN}_MEICA.blur.nii.gz
3dcalc  -overwrite -a pc08.${SBJ}_${RUN}_MEICA.project.nii.gz \
                   -m pc08.${SBJ}_${RUN}_MEICA.MEAN.nii.gz \
                   -expr 'a/m' \
                   -prefix pc09.${SBJ}_${RUN}_MEICA.spc.nii.gz

echo -e "\n"
echo -e "\033[0;32m#====================================#\033[0m"
echo -e "\033[0;32m#  SUCCESSFUL TERMINATION OF SCRIPT  #\033[0m"
echo -e "\033[0;32m#====================================#\033[0m"

