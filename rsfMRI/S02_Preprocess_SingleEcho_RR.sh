source ./00_CommonVariables.sh
set -e

# INPUT VARIABLES REQUIRED
# ========================
if [[ -z "${SBJ}" ]]; then
        echo "You need to provide SBJ as an environment variable"
        exit
fi
if [[ -z "${RUN}" ]]; then
        echo "You need to provide RUN as an environment variable"
        exit
fi
set -e
# NEED TO CREATE FULL BRAIN MASK
# ==============================
MASK_FB_ORIG=`echo ${SBJ}_${RUN}.REF.mask.FBrain.nii.gz`
# This program will generate a copy of the mask in MNI space
MASK_FB_MNI=`echo ${SBJ}_${RUN}.REF.mask.FBrain.MNI.nii.gz`
MNI_MASTER_TEMPLATE=`echo ${PRJDIR}/Scripts/MNI152_T1_2009c_uni.LR2iso+tlrc`
# CREATING AND ENTERING IN TARGET DIR
# ===================================
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
echo  -e "\033[0;36m+++ ------------------------> Creating Target Dir <----------------------------------------\033[0m"
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
cd ../PrcsData/${SBJ}/
if [ ! -d D02_Preprocessed ]; then
   echo "\033[0;31m+++ INFO: Creating directory [D02_Preprocessed]\033[0m"
   mkdir D02_Preprocessed
fi

echo "\033[0;31m+++ INFO: Entering directory [D02_Preprocessed]\033[0m"
cd D02_Preprocessed
echo "\033[0;31m+++ INFO: Creating links to data files...\033[0m"

for e in 01 02 03
do
 if [ ! -f ${SBJ}_${RUN}_E${e}.nii.gz ]; then ln -fvs ../D00_OriginalData/${SBJ}_${RUN}_E${e}.nii.gz .; fi
done

if [ ! -f ${SBJ}_${RUN}_Echoes.1D        ]; then ln -fvs ../D00_OriginalData/${SBJ}_${RUN}_Echoes.1D      .; fi
if [ ! -f ${SBJ}_epi_forward-e01.nii.gz  ]; then ln -fvs ../D00_OriginalData/${SBJ}_epi_forward-e01.nii.gz .; fi 
if [ ! -f ${SBJ}_epi_reverse-e01.nii.gz  ]; then ln -fvs ../D00_OriginalData/${SBJ}_epi_reverse-e01.nii.gz     .; fi 
# DISCARD FIRST 2 VOLUMES 
# =======================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Remove initial 2 volumes  <----------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
  echo "\033[0;31m+++ INFO: Working on echo E${e} ...\033[0m"
  3dcalc -overwrite -a ${SBJ}_${RUN}_E${e}.nii.gz'[2..$]' -expr a -prefix pc00.${SBJ}_${RUN}_E${e}.discard.nii.gz
done
  
# COUNT OUTLIERS
# ==============
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ----------------------------> Count Outliers <-----------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
  3dToutcount -overwrite -automask -fraction -polort 3 -legendre pc00.${SBJ}_${RUN}_E${e}.discard.nii.gz > pc00.${SBJ}_${RUN}_E${e}.outcount.1D
  1deval -a pc00.${SBJ}_${RUN}_E${e}.outcount.1D -expr "1-step(a-0.1)" > pc00.${SBJ}_${RUN}_E${e}.out.cen.1D
done

# SLICE TIMING CORRECTION
# =======================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e  "\033[0;36m+++ ------------------------> Slice Time Correction <--------------------------------------\033[0m"
echo -e  "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
  echo "\033[0;31m+++ INFO: Working on echo E${e} ...\033[0m" 
  3dTshift -overwrite -Fourier -tzero 0 \
           -prefix pc01.${SBJ}_${RUN}_E${e}.tshift.nii.gz \
                   pc00.${SBJ}_${RUN}_E${e}.discard.nii.gz
done

# BLIP UP/BLIP DOWN CORRECTION
# ============================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e  "\033[0;36m+++ ------------------------> Blip Up / Blip Down  <--------------------------------------\033[0m"
echo -e  "\033[0;36m+++ ======================================================================================\033[0m"

# (1) Create Median Datasets
3dTstat -overwrite -median -prefix rm.${SBJ}_${RUN}_E01.blip.med.fwd ${SBJ}_epi_forward-e01.nii
3dTstat -overwrite -median -prefix rm.${SBJ}_${RUN}_E01.blip.med.rev ${SBJ}_epi_reverse-e01.nii

# (2) Automask Median Datasets
3dAutomask -overwrite -apply_prefix rm.${SBJ}_${RUN}_E01.blip.med.masked.fwd rm.${SBJ}_${RUN}_E01.blip.med.fwd+orig
3dAutomask -overwrite -apply_prefix rm.${SBJ}_${RUN}_E01.blip.med.masked.rev rm.${SBJ}_${RUN}_E01.blip.med.rev+orig

# (3) Compute the midpoint warp between the median datasets
3dQwarp -overwrite -plusminus -pmNAMES Rev For                                  \
        -pblur 0.05 0.05 -blur -1 -1                                            \
        -noweight -minpatch 9                                                   \
        -source rm.${SBJ}_${RUN}_E01.blip.med.masked.rev+orig                   \
        -base   rm.${SBJ}_${RUN}_E01.blip.med.masked.fwd+orig                   \
        -prefix ${SBJ}_${RUN}_E01.blip_warp

# (4) Warp  EPI Timeseries
for e in 01 02 03
do
  3dNwarpApply -overwrite -quintic -nwarp ${SBJ}_${RUN}_E01.blip_warp_For_WARP+orig      \
               -source pc01.${SBJ}_${RUN}_E${e}.tshift.nii.gz                 \
               -prefix pc02.${SBJ}_${RUN}_E${e}.blip.nii.gz
  3drefit -atrcopy ${SBJ}_epi_reverse-e01.nii.gz IJK_TO_DICOM_REAL      \
                   pc02.${SBJ}_${RUN}_E${e}.blip.nii.gz
done
3dAutomask -overwrite -eclip -clfrac 0.5 -prefix ${MASK_FB_ORIG} pc02.${SBJ}_${RUN}_E01.blip.nii.gz

rm rm.${SBJ}_${RUN}_E01.blip.med.fwd+orig.*
rm rm.${SBJ}_${RUN}_E01.blip.med.masked.fwd+orig.*
rm rm.${SBJ}_${RUN}_E01.blip.med.masked.rev+orig.*
rm rm.${SBJ}_${RUN}_E01.blip.med.rev+orig.*

# COMPUTE STATIC S0 AND T2S MAPS
# ==============================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Compute Static Maps <----------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dZcat -overwrite -prefix pc02.${SBJ}_${RUN}_ZCAT.blip.nii.gz pc02.${SBJ}_${RUN}_E??.blip.nii.gz

module load python/3.6
# module load Anaconda 
# Environment originally created with:
# conda create --prefix /data/SFIMJGC/PRJ_MEPFM/Apps/envs/mepfm_p36 python=3.6 numpy scipy scikit-learn seaborn nibabel pandas matplotlib sphinx
# source activate /data/RS_preprocess/Apps/envs/inati_meica_p27
python /data/Epilepsy_EEG/Apps/SFIM_ME/rt_tools/me_get_staticT2star.py -d pc02.${SBJ}_${RUN}_ZCAT.blip.nii.gz \
           --tes_file ${SBJ}_${RUN}_Echoes.1D \
           --non_linear \
           --prefix pc02.${SBJ}_${RUN}_STATIC \
           --mask ${MASK_FB_ORIG}
# source deactivate
rm pc02.${SBJ}_${RUN}_ZCAT.blip.nii.gz

# CREATE CSF MASK
# ===============
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Creating CSF Mask <------------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
3dmask_tool -overwrite -inputs ${MASK_FB_ORIG} -dilate_inputs -3 -prefix rm.${SBJ}_${RUN}.eroded.nii.gz
3dcalc      -overwrite -a pc02.${SBJ}_${RUN}_STATIC.sTE.t2s.nii \
                       -m rm.${SBJ}_${RUN}.eroded.nii.gz   \
                       -expr 'ispositive(a-100)*m'         \
                       -prefix rm.${SBJ}_${RUN}.REF.mask.CSF.nii.gz
3dclust -1Dformat -overwrite -nosum -1dindex 0 -1tindex 0 -2thresh -0.5 0.5 -dxyz=1 \
                  -savemask    ${SBJ}_${RUN}.REF.mask.CSF.nii.gz 1.01 20 \
                            rm.${SBJ}_${RUN}.REF.mask.CSF.nii.gz 
3dcalc -overwrite -a ${SBJ}_${RUN}.REF.mask.CSF.nii.gz -expr 'ispositive(a)' -prefix ${SBJ}_${RUN}.REF.mask.CSF.nii.gz
rm rm.${SBJ}_${RUN}.eroded.nii.gz
rm rm.${SBJ}_${RUN}.REF.mask.CSF.nii.gz

# HEAD MOTION CORRECTION
# ======================
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
echo  -e "\033[0;36m+++ ------------------------> Head motion / Aligment <-------------------------------------\033[0m"
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
echo  -e "\033[0;31m+++ INFO: Estimating Motion Parameters using the first echo...\033[0m"
REF4VOLREG=`echo ${SBJ}_${RUN}.REF.nii.gz`
3dbucket -overwrite -prefix ${REF4VOLREG} pc02.${SBJ}_${RUN}_E01.blip.nii.gz'[0]'

3dvolreg -overwrite -verbose -zpad 1                   \
         -1Dmatrix_save ${SBJ}_${RUN}_matrix_intrarun  \
         -maxdisp1D     ${SBJ}_${RUN}_MaxMot.1D        \
         -1Dfile        ${SBJ}_${RUN}_Motion.1D        \
         -base          ${REF4VOLREG}                  \
         -prefix     rm.${SBJ}_${RUN}_E01.volreg.nii.gz \
                   pc02.${SBJ}_${RUN}_E01.blip.nii.gz

rm rm.${SBJ}_${RUN}_E01.volreg.nii.gz

1d_tool.py -overwrite -infile ${SBJ}_${RUN}_Motion.1D -set_nruns 1 -demean             -write ${SBJ}_${RUN}_Motion.demean.1D
1d_tool.py -overwrite -infile ${SBJ}_${RUN}_Motion.1D -set_nruns 1 -derivative -demean -write ${SBJ}_${RUN}_Motion.demean.der.1D
1d_tool.py -overwrite -infile ${SBJ}_${RUN}_MaxMot.1D -derivative -write ${SBJ}_${RUN}_MaxMot.rel.1D

# ALGIN ANATOMICAL TO REFERENCE EPI
# =================================
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
echo  -e "\033[0;36m+++ --------------------> Copying Anat 2 MNI Transformations  <----------------------------\033[0m"
echo  -e "\033[0;36m+++ =======================================================================================\033[0m"
if [ ! -f ${SBJ}_Anat_bc_ns+orig.HEAD    ]; then ln -s ../D01_Anatomical/${SBJ}_Anat_bc_ns+orig.*    .; fi
if [ ! -f ${SBJ}_Anat_bc_ns+tlrc.HEAD    ]; then ln -s ../D01_Anatomical/${SBJ}_Anat_bc_ns+tlrc.*    .; fi
if [ ! -f ${SBJ}_Anat_bc_ns.AB+tlrc.HEAD ]; then ln -s ../D01_Anatomical/${SBJ}_Anat_bc_ns.AB+tlrc.* .; fi
if [ "${doNL}" -eq "0" ]; then
   if [ ! -L ${SBJ}_MNI2Anat.Xaff12.1D ]; then ln -s ../D01_Anatomical/${SBJ}_MNI2Anat.Xaff12.1D .; fi
   if [ ! -L ${SBJ}_Anat2MNI.Xaff12.1D ]; then ln -s ../D01_Anatomical/${SBJ}_Anat2MNI.Xaff12.1D .; fi
else
   if [ ! -L ${SBJ}_Anat_bc_ns_WARP+tlrc.HEAD ]; then ln -s ../D01_Anatomical/${SBJ}_Anat_bc_ns_WARP+tlrc.* .; fi
fi

echo -e "\033[0;31m++ INFO: Bias Correct EPI reference...\033[0m"  
REF4ANAT=`echo ${SBJ}_${RUN}.REF.bc.nii.gz`
REF4ANAT_NS=`echo ${SBJ}_${RUN}.REF.bc.ns.nii.gz`
3dresample -overwrite -inset ../D01_Anatomical/${SBJ}_Anat.UN.Bias+orig -master ${REF4VOLREG} -prefix ${SBJ}_${RUN}.REF.Bias.nii.gz
3drefit -atrcopy ${SBJ}_epi_reverse-e01.nii.gz IJK_TO_DICOM_REAL ${SBJ}_${RUN}.REF.Bias.nii.gz 

3dcalc -overwrite                       \
       -a ${SBJ}_${RUN}.REF.Bias.nii.gz \
       -b ${REF4VOLREG}                 \
       -expr 'b*a'                      \
       -prefix ${REF4ANAT}

echo -e "\033[0;31m++ INFO: Skull strip EPI reference...\033[0m"  
3dcalc -overwrite             \
       -a ${REF4ANAT}          \
       -m ${MASK_FB_ORIG}     \
       -exp 'a*m'             \
       -prefix ${REF4ANAT_NS}

echo "\033[0;31m++ INFO: Zero pad anat (just in case a large displacement is needed)... \033[0m"  
3dZeropad -overwrite -A 10 -P 10 -I 10 -S 10 -R 10 -L 10 -prefix ${SBJ}_Anat_bc_ns.pad ${SBJ}_Anat_bc_ns+orig

echo "\033[0;31m++ INFO: Align ANAT to REF EPI... \033[0m"  
align_epi_anat.py -anat ${SBJ}_Anat_bc_ns.pad+orig  \
                  -epi  ${REF4ANAT_NS} \
                  -epi_base 0 -anat2epi -anat_has_skull no \
                  -epi_strip None \
                  -deoblique on -giant_move \
                  -master_anat SOURCE -overwrite

echo "\033[0;31m++ INFO: Autobox... \033[0m"  
3dAutobox -overwrite -prefix ${SBJ}_Anat_bc_ns_al${RUN} -npad 3 ${SBJ}_Anat_bc_ns.pad_al+orig
3dcopy    -overwrite ${SBJ}_Anat_bc_ns_al${RUN}+orig ${SBJ}_Anat_bc_ns_al${RUN}.nii.gz
#rm ${SBJ}_Anat_bc_ns_al+orig.*
rm ${SBJ}_Anat_bc_ns.pad+orig.*
rm ${SBJ}_Anat_bc_ns.pad_al+orig.*

mv ${SBJ}_Anat_bc_ns.pad_al_mat.aff12.1D ${SBJ}_${RUN}.Anat2REF.Xaff12.1D
if [ -f ${SBJ}_Anat_bc_ns.pad_al_e2a_only_mat.aff12.1D ]; then rm ${SBJ}_Anat_bc_ns.pad_al_e2a_only_mat.aff12.1D; fi
#exit

# CREATE FINAL TRANSFORMATION MATRIX 
# ==================================
echo "\033[0;31m++ INFO: Create all transformation matrices \033[0m"  
cat_matvec -ONELINE ${SBJ}_${RUN}.Anat2REF.Xaff12.1D -I > ${SBJ}_${RUN}.REF2Anat.Xaff12.1D

echo "\033[0;31m++ INFO: Apply Non Linear Transform and Mot Correction  \033[0m"  
for e in 01 02 03
do
echo "\033[0;31m++ INFO: Working on Echo E${e} ...\033[0m"
3dNwarpApply -overwrite \
             -source pc01.${SBJ}_${RUN}_E${e}.tshift.nii.gz \
             -nwarp ''''../D01_Anatomical/${SBJ}'''_Anat_bc_ns_WARP+tlrc '''${SBJ}'''_'''${RUN}'''.REF2Anat.Xaff12.1D '''${SBJ}'''_'''${RUN}'''_matrix_intrarun.aff12.1D '''${SBJ}'''_'''${RUN}'''_E01.blip_warp_For_WARP+orig'\
             -master ${MNI_MASTER_TEMPLATE} \
             -prefix pc03.${SBJ}_${RUN}_E${e}.volreg.nii.gz
done

echo "\033[0;31m++ INFO: Working on Static S0 map...\033[0m"
3dNwarpApply -overwrite  \
             -source pc02.${SBJ}_${RUN}_STATIC.sTE.S0.nii \
             -nwarp ''''../D01_Anatomical/${SBJ}'''_Anat_bc_ns_WARP+tlrc '''${SBJ}'''_'''${RUN}'''.REF2Anat.Xaff12.1D '''${SBJ}'''_'''${RUN}'''_matrix_intrarun.aff12.1D '''${SBJ}'''_'''${RUN}'''_E01.blip_warp_For_WARP+orig' \
             -master ${MNI_MASTER_TEMPLATE} \
             -prefix ${SBJ}_${RUN}_STATIC.sTE.S0.MNI.nii

echo "\033[0;31m++ INFO: Working on Full Brain Mask... \033[0m"
3dNwarpApply -overwrite -ainterp NN \
             -source ${MASK_FB_ORIG} \
             -nwarp ''''../D01_Anatomical/${SBJ}'''_Anat_bc_ns_WARP+tlrc '''${SBJ}'''_'''${RUN}'''.REF2Anat.Xaff12.1D '''${SBJ}'''_'''${RUN}'''_matrix_intrarun.aff12.1D '''${SBJ}'''_'''${RUN}'''_E01.blip_warp_For_WARP+orig' \
             -master ${MNI_MASTER_TEMPLATE} \
             -prefix ${MASK_FB_MNI}

# REGRESS SIGNALS OF NO INTEREST
# ==============================
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Create Physio Regressor <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
  echo "\033[0;31m++ INFO: Working on Echo E${e} ...\033[0m"
  3dpc -overwrite -dmean -pcsave 5 -mask ${SBJ}_${RUN}.REF.mask.CSF.nii.gz -prefix ${SBJ}_${RUN}_E${e}.CSF.PCA pc01.${SBJ}_${RUN}_E${e}.tshift.nii.gz
  rm ${SBJ}_${RUN}_E${e}.CSF.PCA??.1D
  rm ${SBJ}_${RUN}_E${e}.CSF.PCA_eig.1D
  rm ${SBJ}_${RUN}_E${e}.CSF.PCA+orig.*
done
 
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Remove Nuisance Signals <------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
    echo "\033[0;31m++ INFO: Working on Echo E${e} ...\033[0m"
    3dTproject -overwrite                                      \
               -mask ${MASK_FB_MNI}                            \
               -input  pc03.${SBJ}_${RUN}_E${e}.volreg.nii.gz  \
               -prefix pc04.${SBJ}_${RUN}_E${e}.project.nii.gz \
               -blur 6                                         \
               -polort 5                                       \
               -ort ${SBJ}_${RUN}_Motion.demean.1D             \
               -ort ${SBJ}_${RUN}_Motion.demean.der.1D         \
               -ort ${SBJ}_${RUN}_E${e}.CSF.PCA_vec.1D                 
done

# CONVERT TO SPC
# ==============
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
echo -e "\033[0;36m+++ ------------------------> Convert to SPC <---------------------------------------------\033[0m"
echo -e "\033[0;36m+++ =======================================================================================\033[0m"
for e in 01 02 03
do
  echo "\033[0;31m++ INFO: Working on Echo E${e} ...\033[0m"
  # (1) Compute a similarly blur version of the data without the regression (To obtain the mean signal per voxel)
  3dBlurInMask -overwrite -FWHM 6 \
                -mask        ${MASK_FB_MNI} \
                -input  pc03.${SBJ}_${RUN}_E${e}.volreg.nii.gz \
                -prefix pc04.${SBJ}_${RUN}_E${e}.blur.nii.gz
  # (2) Compute the mean signal per voxel using this blurred version
  3dTstat -overwrite -mean \
                -prefix pc04.${SBJ}_${RUN}_E${e}.MEAN.nii.gz \
                        pc04.${SBJ}_${RUN}_E${e}.blur.nii.gz
  # (3) As the project version has no mean already, all that's left is the division
  3dcalc  -overwrite -a pc04.${SBJ}_${RUN}_E${e}.project.nii.gz \
                     -m pc04.${SBJ}_${RUN}_E${e}.MEAN.nii.gz \
                     -expr 'a/m' \
                     -prefix pc05.${SBJ}_${RUN}_E${e}.spc.nii.gz
  # (4) Remove the blurred version used to compute the MEAN (to avoid confussion)
  rm pc04.${SBJ}_${RUN}_E${e}.blur.nii.gz
done
